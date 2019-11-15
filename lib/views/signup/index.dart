import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:redux/redux.dart';
import 'package:flutter_redux/flutter_redux.dart';

import 'package:Tether/domain/index.dart';
import 'package:Tether/domain/user/model.dart';

// Styling Widgets
import 'package:flutter_swiper/flutter_swiper.dart';
import 'package:touchable_opacity/touchable_opacity.dart';
import 'package:Tether/global/colors.dart';

import './step-username.dart';
import './step-password.dart';
import './step-homeserver.dart';

class Signup extends StatefulWidget {
  final String title;
  const Signup({Key key, this.title}) : super(key: key);

  SignupState createState() => SignupState(title: this.title);
}

class SignupState extends State<Signup> {
  final String title;
  final double DEFAULT_INPUT_HEIGHT = 52;
  final double DEFAULT_BUTTON_HEIGHT = 48;
  final sections = [
    UsernameStep(),
    PasswordStep(),
    HomeserverStep(),
  ];

  int currentStep = 0;
  bool onboarding = false;
  SwiperController controller;

  SignupState({Key key, this.title});

  @override
  void initState() {
    controller = new SwiperController();
  }

  Widget buildButtonText() {
    switch (currentStep) {
      case 4:
        return const Text('Finish',
            style: TextStyle(fontSize: 20, color: Colors.white));
      default:
        return const Text('Continue',
            style: TextStyle(fontSize: 20, color: Colors.white));
    }
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Spacer(flex: 8),
          Container(
              width: width,
              height: height * 0.6,
              constraints:
                  BoxConstraints(minWidth: 125, minHeight: 345, maxHeight: 400),
              child: Swiper(
                itemBuilder: (BuildContext context, int index) {
                  return sections[index];
                },
                onIndexChanged: (index) {
                  setState(() {
                    currentStep = index;
                  });
                },
                loop: false,
                itemCount: 5,
                controller: controller,
              )),
          Spacer(flex: 9),
          StoreConnector<AppState, UserStore>(
            converter: (Store<AppState> store) => store.state.userStore,
            builder: (context, userStore) {
              return Container(
                width: width * 0.7,
                height: DEFAULT_BUTTON_HEIGHT,
                margin: const EdgeInsets.all(10.0),
                constraints: BoxConstraints(
                    minWidth: 200, maxWidth: 400, minHeight: 45, maxHeight: 65),
                child: FlatButton(
                    disabledColor: Colors.grey,
                    disabledTextColor: Colors.grey[300],
                    onPressed: !userStore.isUsernameValid
                        ? null
                        : () {
                            if (currentStep != sections.length - 1) {
                              setState(() {
                                onboarding = true;
                              });
                              controller.next(animation: true);
                            }
                          },
                    color: Theme.of(context).primaryColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: new BorderRadius.circular(30.0)),
                    child: buildButtonText()),
              );
            },
          ),
          Spacer(flex: 3),
        ],
      )),
    );
  }
}