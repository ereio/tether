import 'dart:async';
import 'dart:io';

// Store
import 'package:Tether/global/dimensions.dart';
import 'package:Tether/store/crypto/actions.dart';
import 'package:Tether/store/rooms/room/model.dart';
import 'package:Tether/global/themes.dart';
import 'package:Tether/store/rooms/room/selectors.dart';
import 'package:Tether/views/home/chat/details-message.dart';
import 'package:Tether/views/home/chat/details-chat.dart';
import 'package:Tether/views/widgets/chat-input.dart';
import 'package:Tether/views/widgets/image-matrix.dart';
import 'package:Tether/views/widgets/message-typing.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_redux/flutter_redux.dart';

// Store
import 'package:redux/redux.dart';
import 'package:Tether/store/index.dart';
import 'package:Tether/store/rooms/events/model.dart';
import 'package:Tether/store/rooms/events/selectors.dart';
import 'package:Tether/store/rooms/selectors.dart' as roomSelectors;
import 'package:Tether/store/rooms/events/actions.dart';

// Global widgets
import 'package:Tether/views/widgets/message.dart';

// Styling
import 'package:Tether/global/colors.dart';
import 'package:Tether/views/widgets/menu.dart';

/**
 * Resources:
 * https://stackoverflow.com/questions/45900387/multi-line-textfield-in-flutter
 * https://stackoverflow.com/questions/50400529/how-to-update-flutter-textfields-height-and-width
 * https://stackoverflow.com/questions/55863766/how-to-prevent-keyboard-from-dismissing-on-pressing-submit-key-in-flutter
 * https://medium.com/nonstopio/make-the-list-auto-scrollable-when-you-add-the-new-message-in-chat-messages-functionality-in-19e457a838a7
 * 
 */
enum ChatOptions {
  search,
  allMedia,
  chatSettings,
  inviteFriends,
  muteNotifications
}

class ChatViewArguements {
  final String roomId;
  final String title;

  // Improve loading times
  ChatViewArguements({
    this.roomId,
    this.title,
  });
}

class ChatView extends StatefulWidget {
  const ChatView({Key key}) : super(key: key);

  @override
  ChatViewState createState() => ChatViewState();
}

class ChatViewState extends State<ChatView> {
  Timer typingNotifier;
  Timer typingNotifierTimeout;
  FocusNode inputFieldNode;
  Map<String, Color> senderColors;
  bool sendable = false;
  Message selectedMessage;

  double overshoot = 0;
  bool loadMore = false;
  String inputType = MediumType.plaintext;
  final editorController = TextEditingController();
  final messagesController = ScrollController();
  final listViewController = ScrollController();

  @override
  void initState() {
    super.initState();
    inputFieldNode = FocusNode();
    inputFieldNode.addListener(() {
      if (!inputFieldNode.hasFocus && this.typingNotifier != null) {
        this.typingNotifier.cancel();
        this.setState(() {
          typingNotifier = null;
        });
      }
    });

    SchedulerBinding.instance.addPostFrameCallback((_) {
      onMounted();
    });
  }

  @protected
  void onMounted() {
    final arguements =
        ModalRoute.of(context).settings.arguments as ChatViewArguements;
    final store = StoreProvider.of<AppState>(context);
    final props = _Props.mapStoreToProps(store, arguements.roomId);
    final draft = props.room.draft;

    if (props.room.encryptionEnabled) {
      store.dispatch(
        fetchDeviceKeys(users: props.room.users),
      );
    }

    if (props.room.messages.length < 10) {
      props.onLoadFirstBatch();
    }

    messagesController.addListener(() {
      final extentBefore = messagesController.position.extentBefore;
      final max = messagesController.position.maxScrollExtent;

      final limit = max - extentBefore;
      final atLimit = Platform.isAndroid ? limit < 1 : limit < -32;

      if (atLimit && !loadMore) {
        this.setState(() {
          loadMore = true;
        });
        props.onLoadMoreMessages();
      } else if (!atLimit && loadMore && !props.loading) {
        this.setState(() {
          loadMore = false;
        });
      }
    });

    if (draft != null && draft.type == MessageTypes.TEXT) {
      final text = draft.body;
      this.setState(() {
        sendable = text != null && text.isNotEmpty;
      });

      editorController.value = TextEditingValue(
        text: text,
        selection: TextSelection.fromPosition(
          TextPosition(
            offset: text.length,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    inputFieldNode.dispose();
    messagesController.dispose();
    super.dispose();
    if (this.typingNotifier != null) {
      this.typingNotifier.cancel();
    }

    if (this.typingNotifierTimeout != null) {
      this.typingNotifierTimeout.cancel();
    }
  }

  @protected
  onUpdateMessage(String text, _Props props) {
    this.setState(() {
      sendable = text != null && text.isNotEmpty;
    });

    // start an interval for updating typing status
    if (inputFieldNode.hasFocus && this.typingNotifier == null) {
      props.onSendTyping(typing: true, roomId: props.room.id);
      this.setState(() {
        typingNotifier = Timer.periodic(
          Duration(milliseconds: 4000),
          (timer) => props.onSendTyping(typing: true, roomId: props.room.id),
        );
      });
    }

    // Handle a timeout of the interval if the user idles with input focused
    if (inputFieldNode.hasFocus) {
      if (typingNotifierTimeout != null) {
        this.typingNotifierTimeout.cancel();
      }
      this.setState(() {
        typingNotifierTimeout = Timer(Duration(milliseconds: 4000), () {
          if (typingNotifier != null) {
            this.typingNotifier.cancel();
            this.setState(() {
              typingNotifier = null;
              typingNotifierTimeout = null;
            });
            // run after to avoid flickering
            props.onSendTyping(typing: false, roomId: props.room.id);
          }
        });
      });
    }
  }

  @protected
  onToggleMessageOptions({Message message}) {
    this.setState(() {
      selectedMessage = message;
    });
  }

  @protected
  onToggleMediumOptions(context) async {
    double width = MediaQuery.of(context).size.height;
    double height = MediaQuery.of(context).size.height;
    final newInputType = await showMenu(
      elevation: 4.0,
      context: context,
      position: RelativeRect.fromLTRB(
        width,
        // input height and padding
        height - Dimensions.inputSizeMin,
        0.0,
        0.0,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      items: [
        PopupMenuItem<String>(
          child: Container(
            margin: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.only(right: 8),
                  child: CircleAvatar(
                    backgroundColor: const Color(DISABLED_GREY),
                    child: Stack(children: [
                      Positioned(
                        right: 0,
                        bottom: -1.5,
                        child: Icon(
                          Icons.lock_open,
                          size: Dimensions.miniLockSize,
                          color: Colors.white,
                        ),
                      ),
                      Icon(
                        Icons.send,
                        size: Dimensions.iconSizeLite,
                        color: Colors.white,
                      ),
                    ]),
                  ),
                ),
                Text('Unencrypted'),
              ],
            ),
          ),
          value: MediumType.plaintext,
        ),
        PopupMenuItem<String>(
          child: Container(
            margin: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.only(right: 8),
                  child: CircleAvatar(
                    backgroundColor: Theme.of(context).primaryColor,
                    child: Stack(children: [
                      Positioned(
                        right: 0,
                        bottom: -1.5,
                        child: Icon(
                          Icons.lock,
                          size: Dimensions.miniLockSize,
                          color: Colors.white,
                        ),
                      ),
                      Icon(
                        Icons.send,
                        size: Dimensions.iconSizeLite,
                        color: Colors.white,
                      ),
                    ]),
                  ),
                ),
                Text('Encrypted'),
              ],
            ),
          ),
          value: MediumType.encrypted,
        ),
      ],
    );
    print(newInputType);
    setState(() {
      inputType = newInputType;
    });
  }

  @protected
  onDismissMessageOptions() {
    this.setState(() {
      selectedMessage = null;
    });
  }

  Widget buildMessageList(
    BuildContext context,
    _Props props,
  ) {
    final messages = props.messages;

    return GestureDetector(
      onTap: onDismissMessageOptions,
      child: Container(
        child: ListView(
          reverse: true,
          padding: EdgeInsets.only(bottom: 12),
          physics: selectedMessage != null
              ? const NeverScrollableScrollPhysics()
              : null,
          controller: messagesController,
          children: [
            MessageTypingWidget(
              typing: props.room.userTyping,
              usersTyping: props.room.usersTyping,
              roomUsers: props.room.users,
              selectedMessageId:
                  this.selectedMessage != null ? this.selectedMessage.id : null,
            ),
            ListView.builder(
              reverse: true,
              shrinkWrap: true,
              padding: EdgeInsets.only(bottom: 4),
              addRepaintBoundaries: true,
              addAutomaticKeepAlives: true,
              itemCount: messages.length,
              scrollDirection: Axis.vertical,
              // controller: messagesController,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (BuildContext context, int index) {
                final message = messages[index];
                final lastMessage = index != 0 ? messages[index - 1] : null;
                final nextMessage =
                    index + 1 < messages.length ? messages[index + 1] : null;

                final isLastSender =
                    lastMessage != null && lastMessage.sender == message.sender;
                final isNextSender =
                    nextMessage != null && nextMessage.sender == message.sender;
                final isUserSent = props.userId == message.sender;
                final selectedMessageId = this.selectedMessage != null
                    ? this.selectedMessage.id
                    : null;

                final avatarUri = props.room.users[message.sender]?.avatarUri;

                return MessageWidget(
                  message: message,
                  isUserSent: isUserSent,
                  isLastSender: isLastSender,
                  isNextSender: isNextSender,
                  lastRead: props.room.lastRead,
                  selectedMessageId: selectedMessageId,
                  onLongPress: onToggleMessageOptions,
                  avatarUri: avatarUri,
                  theme: props.theme,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /**
     * TODO: Room Drafts
     */
  // if (props.room.isDraftRoom) {
  //   final convertedRoomId = await props.onConvertDraftRoom();
  //   final arguements =
  //       ModalRoute.of(context).settings.arguments as ChatViewArguements;
  //   Navigator.of(context).pushReplacementNamed(
  //     '/home/chat',
  //     arguments: ChatViewArguements(
  //       roomId: convertedRoomId.id,
  //       title: arguements.title,
  //     ),
  //   );
  // }

  @protected
  onSubmitMessage(_Props props) async {
    print(editorController.text);
    props.onSendMessage(
      body: editorController.text,
      type: MessageTypes.TEXT,
    );
    editorController.clear();
    FocusScope.of(context).unfocus();
  }

  @protected
  buildRoomAppBar({
    _Props props,
    BuildContext context,
  }) {
    return AppBar(
      brightness: Brightness.dark, // TOOD: this should inherit from theme
      automaticallyImplyLeading: false,
      titleSpacing: 0.0,
      title: Row(
        children: <Widget>[
          Container(
            margin: EdgeInsets.only(left: 8),
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                if (editorController.text != null &&
                    0 < editorController.text.length)
                  props.onSaveDraftMessage(
                    body: editorController.text,
                    type: MessageTypes.TEXT,
                  );
                Navigator.pop(context, false);
              },
            ),
          ),
          GestureDetector(
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              child: Stack(
                children: [
                  Hero(
                      tag: "ChatAvatar",
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: props.roomPrimaryColor,
                        child: props.room.avatarUri != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  Dimensions.thumbnailSizeMax,
                                ),
                                child: MatrixImage(
                                  width: Dimensions.avatarSize,
                                  height: Dimensions.avatarSize,
                                  mxcUri: props.room.avatarUri,
                                ),
                              )
                            : Text(
                                formatRoomInitials(room: props.room),
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                      )),
                  Visibility(
                    visible: props.room.encryptionEnabled,
                    child: Positioned(
                      bottom: 0,
                      right: 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          Dimensions.thumbnailSizeMax,
                        ),
                        child: Container(
                          height: 16,
                          width: 16,
                          color: Colors.green,
                          child: Icon(
                            Icons.lock,
                            color: Colors.white,
                            size: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            onTap: () {
              Navigator.pushNamed(
                context,
                '/home/chat/settings',
                arguments: ChatSettingsArguments(
                  roomId: props.room.id,
                  title: props.room.name,
                ),
              );
            },
          ),
          Text(
            props.room.name,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w100,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        RoundedPopupMenu<ChatOptions>(
          onSelected: (ChatOptions result) {
            switch (result) {
              case ChatOptions.chatSettings:
                return Navigator.pushNamed(
                  context,
                  '/home/chat/settings',
                  arguments: ChatSettingsArguments(
                    roomId: props.room.id,
                    title: props.room.name,
                  ),
                );
              default:
                break;
            }
          },
          icon: Icon(Icons.more_vert, color: Colors.white),
          itemBuilder: (BuildContext context) => <PopupMenuEntry<ChatOptions>>[
            const PopupMenuItem<ChatOptions>(
              value: ChatOptions.search,
              child: Text('Search'),
            ),
            const PopupMenuItem<ChatOptions>(
              value: ChatOptions.allMedia,
              child: Text('All Media'),
            ),
            const PopupMenuItem<ChatOptions>(
              value: ChatOptions.chatSettings,
              child: Text('Chat Settings'),
            ),
            const PopupMenuItem<ChatOptions>(
              value: ChatOptions.inviteFriends,
              child: Text('Invite Friends'),
            ),
            const PopupMenuItem<ChatOptions>(
              value: ChatOptions.muteNotifications,
              child: Text('Mute Notifications'),
            ),
          ],
        )
      ],
    );
  }

  @protected
  buildMessageOptionsBar({
    _Props props,
    BuildContext context,
  }) {
    return AppBar(
      brightness: Brightness.dark, // TOOD: this should inherit from theme
      backgroundColor: Colors.grey[500],
      automaticallyImplyLeading: false,
      titleSpacing: 0.0,
      title: Row(
        children: <Widget>[
          Container(
            margin: EdgeInsets.only(left: 8),
            child: IconButton(
              icon: Icon(Icons.close, color: Colors.white),
              onPressed: onDismissMessageOptions,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        IconButton(
          icon: Icon(Icons.info),
          tooltip: 'Message Details',
          color: Colors.white,
          onPressed: () => {
            Navigator.pushNamed(
              context,
              '/home/chat/details',
              arguments: MessageDetailArguments(
                roomId: props.room.id,
                message: selectedMessage,
              ),
            ),
            this.setState(() {
              selectedMessage = null;
            })
          },
        ),
        IconButton(
            icon: Icon(Icons.delete),
            iconSize: 28.0,
            tooltip: 'Delete Message',
            color: Colors.white,
            onPressed: () {
              props.onDeleteMessage(
                message: this.selectedMessage,
              );
              this.setState(() {
                selectedMessage = null;
              });
            }),
        Visibility(
          visible: isTextMessage(message: selectedMessage),
          child: IconButton(
            icon: Icon(Icons.content_copy),
            iconSize: 22.0,
            tooltip: 'Copy Message Content',
            color: Colors.white,
            onPressed: () {
              Clipboard.setData(
                ClipboardData(
                  text: selectedMessage.formattedBody ?? selectedMessage.body,
                ),
              );
              this.setState(() {
                selectedMessage = null;
              });
            },
          ),
        ),
        IconButton(
          icon: Icon(Icons.reply),
          iconSize: 28.0,
          tooltip: 'Quote and Reply',
          color: Colors.white,
          onPressed: () {},
        ),
        IconButton(
          icon: Icon(Icons.share),
          iconSize: 24.0,
          tooltip: 'Search Chats',
          color: Colors.white,
          onPressed: () {},
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Props>(
        distinct: true,
        converter: (Store<AppState> store) => _Props.mapStoreToProps(
          store,
          (ModalRoute.of(context).settings.arguments as ChatViewArguements)
              .roomId,
        ),
        builder: (context, props) {
          double height = MediaQuery.of(context).size.height;
          final closedInputPadding = !inputFieldNode.hasFocus &&
              Platform.isIOS &&
              Dimensions.buttonlessHeightiOS < height;

          final isScrolling =
              messagesController.hasClients && messagesController.offset != 0;

          Color inputContainerColor = Colors.white;

          if (Theme.of(context).brightness == Brightness.dark) {
            inputContainerColor = Theme.of(context).scaffoldBackgroundColor;
          }

          var currentAppBar = buildRoomAppBar(
            props: props,
            context: context,
          );

          if (this.selectedMessage != null) {
            currentAppBar = buildMessageOptionsBar(
              props: props,
              context: context,
            );
          }

          return Scaffold(
            appBar: currentAppBar,
            backgroundColor: selectedMessage != null
                ? Theme.of(context).scaffoldBackgroundColor.withAlpha(64)
                : Theme.of(context).scaffoldBackgroundColor,
            body: Align(
              alignment: Alignment.topRight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        // Disimiss keyboard if they click outside the text input
                        inputFieldNode.unfocus();
                        FocusScope.of(context).unfocus();
                      },
                      child: Stack(
                        children: [
                          buildMessageList(
                            context,
                            props,
                          ),
                          Positioned(
                            child: Visibility(
                              visible: props.loading,
                              child: Container(
                                  child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  RefreshProgressIndicator(
                                    strokeWidth: Dimensions.defaultStrokeWidth,
                                    valueColor:
                                        new AlwaysStoppedAnimation<Color>(
                                      PRIMARY_COLOR,
                                    ),
                                    value: null,
                                  ),
                                ],
                              )),
                            ),
                          ),
                          Positioned(
                            child: Visibility(
                              visible: props.loading,
                              child: Container(
                                  child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  RefreshProgressIndicator(
                                    strokeWidth: Dimensions.defaultStrokeWidth,
                                    valueColor:
                                        new AlwaysStoppedAnimation<Color>(
                                      PRIMARY_COLOR,
                                    ),
                                    value: null,
                                  ),
                                ],
                              )),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.only(
                      left: 8,
                      right: 8,
                      top: 12,
                      bottom: 12,
                    ),
                    decoration: BoxDecoration(
                      color: inputContainerColor,
                      boxShadow: isScrolling
                          ? [
                              BoxShadow(
                                  blurRadius: 6,
                                  offset: Offset(0, -4),
                                  color: Colors.black12)
                            ]
                          : [],
                    ),
                    child: AnimatedPadding(
                      duration: Duration(
                          milliseconds: inputFieldNode.hasFocus ? 225 : 0),
                      padding: EdgeInsets.only(
                        bottom: closedInputPadding ? 16 : 0,
                      ),
                      child: ChatInput(
                        sendable: sendable,
                        focusNode: inputFieldNode,
                        controller: editorController,
                        onChangeMethod: () => onToggleMediumOptions(context),
                        onChangeMessage: (text) => onUpdateMessage(text, props),
                        onSubmitMessage: () => this.onSubmitMessage(props),
                        onSubmittedMessage: (text) =>
                            this.onSubmitMessage(props),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class _Props extends Equatable {
  final Room room;
  final String userId;
  final List<Message> messages;
  final bool loading;
  final ThemeType theme;
  final Color roomPrimaryColor;

  final Function onSendTyping;
  final Function onSendMessage;
  final Function onDeleteMessage;
  final Function onSaveDraftMessage;
  final Function onLoadMoreMessages;
  final Function onLoadFirstBatch;

  _Props({
    @required this.room,
    @required this.theme,
    @required this.userId,
    @required this.messages,
    @required this.loading,
    @required this.roomPrimaryColor,
    @required this.onSendTyping,
    @required this.onSendMessage,
    @required this.onDeleteMessage,
    @required this.onSaveDraftMessage,
    @required this.onLoadMoreMessages,
    @required this.onLoadFirstBatch,
  });

  static _Props mapStoreToProps(Store<AppState> store, String roomId) => _Props(
      userId: store.state.authStore.user.userId,
      theme: store.state.settingsStore.theme,
      loading: roomSelectors
          .room(
            id: roomId,
            state: store.state,
          )
          .syncing,
      room: roomSelectors.room(
        id: roomId,
        state: store.state,
      ),
      messages: latestMessages(
        wrapOutboxMessages(
          messages: roomSelectors.room(id: roomId, state: store.state).messages,
          outbox: roomSelectors.room(id: roomId, state: store.state).outbox,
        ),
      ),
      roomPrimaryColor: () {
        final customChatSettings =
            store.state.settingsStore.customChatSettings ?? Map();

        if (customChatSettings[roomId] != null) {
          return Color(customChatSettings[roomId].primaryColor);
        }

        return Colors.grey;
      }(),
      onSaveDraftMessage: ({
        String body,
        String type,
      }) {
        store.dispatch(saveDraft(
          body: body,
          type: type,
          room: store.state.roomStore.rooms[roomId],
        ));
      },
      onSendMessage: ({
        String body,
        String type,
      }) async {
        store.dispatch(sendMessage(
          body: body,
          room: store.state.roomStore.rooms[roomId],
          type: type,
        ));
      },
      onDeleteMessage: ({
        Message message,
      }) {
        if (message != null) {
          store.dispatch(deleteMessage(message: message));
        }
      },
      onSendTyping: ({typing, roomId}) => store.dispatch(
            sendTyping(
              typing: typing,
              roomId: roomId,
            ),
          ),
      onLoadFirstBatch: () {
        final room = roomSelectors.room(
          id: roomId,
          state: store.state,
        );

        store.dispatch(
          fetchMessageEvents(
            room: room,
          ),
        );
      },
      onLoadMoreMessages: () {
        final room = roomSelectors.room(
          id: roomId,
          state: store.state,
        );

        store.dispatch(fetchMessageEvents(
          room: room,
          startHash: room.endHash,
        ));
      }

      /**
         * TODO: Room Drafts
         */
      // onConvertDraftRoom: () async {
      //   final room = store.state.roomStore.rooms[roomId];
      //   return store.dispatch(convertDraftRoom(room: room));
      // },
      );

  @override
  List<Object> get props => [
        userId,
        messages,
        room,
        roomPrimaryColor,
        loading,
      ];
}
