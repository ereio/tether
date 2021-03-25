import 'package:redux/redux.dart';
import 'package:syphon/global/print.dart';
import 'package:syphon/storage/index.dart';
import 'package:syphon/store/events/actions.dart';
import 'package:syphon/store/events/messages/storage.dart';
import 'package:syphon/store/events/storage.dart';
import 'package:syphon/store/index.dart';

///
/// Messages Storage Middleware
///
/// Saves message data to cold storage based
/// on which redux actions are fired, happens
/// BEFORE updating state with
///
dynamic storageMiddlewareMessages<State>(
  Store<AppState> store,
  dynamic action,
  NextDispatcher next,
) {
  try {
    switch (action.runtimeType) {
      case SetMessages:
        final messages = (action as SetMessages).messages;
        if (messages == null || messages.length == 0) {
          break;
        }
        saveMessages(messages, storage: Storage.main);
        break;
      default:
        break;
    }
  } catch (error) {
    printError(error.toString(), tag: 'storageMiddlewareMessages');
  }

  next(action);
}
