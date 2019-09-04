/**
 * Sample React Native App
 * https://github.com/facebook/react-native
 *
 * @format
 * @flow
 */

import React, {Fragment} from 'react';
import {SafeAreaView, StyleSheet, NativeModules} from 'react-native';

var navDemo = NativeModules.NavDemo;
navDemo.renderNaviDemo(
  (originLat = -37.8182668),
  (originLon = 144.9648731),
  (originName = 'Flinder Station'),
  (destinationLat = -37.8165647),
  (destinationLon = 144.9475055),
  (destinationName = 'Marvel Stadium'),
);

const App = () => {
  return <SafeAreaView></SafeAreaView>;
};

const styles = StyleSheet.create({});

export default App;
