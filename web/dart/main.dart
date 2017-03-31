/*
 * Tern Tangible Programming Language
 * Copyright (c) 2016 Michael S. Horn
 *
 *           Michael S. Horn (michael-horn@northwestern.edu)
 *           Northwestern University
 *           2120 Campus Drive
 *           Evanston, IL 60613
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License (version 2) as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */
library rppt;

import 'dart:html';
import 'dart:math';
import 'dart:async';
import 'dart:js';

part 'compiler.dart';
part 'connector.dart';
part 'factory.dart';
part 'program.dart';
part 'scanner.dart';
part 'statement.dart';
part 'topcode.dart';
part 'utils.dart';


// IMPORTANT! This has to match js/video.js
const VIDEO_WIDTH = 1280; //1920; // 1280; // 800
const VIDEO_HEIGHT = 720; // 1080; // 720; // 600

RPPT rppt;



void main() {
  var timer = new Timer(new Duration(seconds: 5), () => rppt = new RPPT());
}


class RPPT {

  /* <canvas> tag drawing context */
  CanvasRenderingContext2D ctx;

  /* this is going to find all of our physical components */
  Scanner scanner;

  /* we need this to do the computer vision work */
  VideoElement video = null;

  Timer timer;

  var codeDict = new Map();

  var session = context['session'];

  // topcode state flags
  bool kbPresent = false;
  bool camPresent = false;
  bool photoPresent = false;
  bool mapPresent = false;
  bool callTransperancy = true;


  RPPT() {
    CanvasElement canvas = querySelector("#video-canvas");
    ctx = canvas.getContext("2d");
    scanner = new Scanner();
    video = querySelector("#video-stream");

    video.autoplay = true;
    video.onPlay.listen((e) {
      timer = new Timer.periodic(const Duration(milliseconds : 100), refreshCanvas);
    });
  }


/**
 * Stop the video stream.
 *  Note: it's possible to stop the video from dart, but we probably won't need this...
 */
  void stopVideo() {
    video.pause();
    if (timer != null) timer.cancel();
  }


/*
 * Called 30 frames a second while the camera is on
 */
  void refreshCanvas(Timer timer) {

    // javascript will change this class name as a signal to dart to stop scanning
    if (video.className == "stopped") {
      timer.cancel();
      print("stopping scan");
      return;
    }

    // draw a frame from the video stream onto the canvas (flipped horizontally)
    ctx.save();
    {
      ctx.translate(video.videoWidth, 0);
      ctx.scale(-1, 1);
      ctx.drawImage(video, 0, 0);
    }
    ctx.restore();


    // grab a bitphoto from the canvas
    ImageData id = ctx.getImageData(0, 0, video.videoWidth, video.videoHeight);
    List<TopCode> codes = scanner.scan(id, ctx);


    for (TopCode top in codes) {
      ctx.fillStyle = "rgba(0, 255, 255, 0.5)";
      ctx.fillRect(top.x - top.radius, top.y - top.radius, top.diameter, top.diameter);
      // print([top.code, top.radius, top.x, top.y]);
      codeDict[top.code] = [6, top.radius, top.x, top.y];
    }

    parseCodes(codeDict);
  }

  static int xOffset = 892;
  static int yOffset = 20;
  static int xRange = 455;
  static int yRange = 650;
  static double iosWidth = 375.0; // actual width
  static double iosHeight = iosWidth * 1.4375; // height of stream element
  static double iosMenuBar = 20.0;
  List<double> transformIos(double x1, double x2, double y1, double y2) {
    return [
      (xOffset - x1) * (iosWidth / xRange),
      (xOffset - x2) * (iosWidth / xRange),
      (y1 - yOffset) * (iosHeight / yRange) + iosMenuBar,
      (y2 - yOffset) * (iosHeight / yRange) + iosMenuBar
    ];
  }

  static double extra = 10.0;
  List<double> fetchCoordinates(List<double> topLeft, List<double> topRight,
      List<double> bottomLeft) {
    double radius = topLeft[1];
    return [
      topLeft[2] + 2 * radius + extra,  // x1
      topLeft[3] - 2 * radius - extra, // y1
      topRight[2] + extra, // x2
      bottomLeft[3] - extra, // y2
    ];
  }

  void parseCodes(Map cd) {
    var toRemove = [];

    // time to live frame calculation
    for (int key in cd.keys){
      if (cd[key][0] > 0){
        cd[key][0] = cd[key][0] - 1;
      }
      else{
        toRemove.add(key);
      }
    }

    for(int e in toRemove){
      cd.remove(e);
    }

    //check for code triggers
    // keyboard – topcode 31
    if (cd.containsKey(31) && !kbPresent){
      print('showKeyboard');
      context['Meteor'].callMethod('call', ['showKeyboard', session]);
      kbPresent = true;
    }
    else if (kbPresent && !cd.containsKey(31)){
      print('hideKeyboard');
      context['Meteor'].callMethod('call', ['hideKeyboard', session]);
      kbPresent = false;
    }

    // camera – 361
    if (cd.containsKey(361) && !camPresent){
      print('showCamera');
      context['Meteor'].callMethod('call', ['showCamera', session]);
      camPresent = true;
    }
    else if (camPresent && !cd.containsKey(361)){
      print('hideCamera');
      context['Meteor'].callMethod('call', ['hideCamera', session]);
      camPresent = false;
    }

    // photo
    // 93 – top L; 155 – top  R; 203 – bottom L; 271 – bottom R
    if (cd.containsKey(93) && cd.containsKey(155) && cd.containsKey(203) && cd.containsKey(271)){
      print('show photo');
      List<double> coordinates = fetchCoordinates(cd[93], cd[155], cd[203]);
      double x1_web = coordinates[0]; // top left
      double y1_web = coordinates[1];
      double x2_web = coordinates[2]; // top right
      double y2_web = coordinates[3]; // bottom left

      List<double> transformed = transformIos(x1_web, x2_web, y1_web, y2_web);
      double x1_ios = transformed[0];
      double x2_ios = transformed[1];
      double y1_ios = transformed[2];
      double y2_ios = transformed[3];

      double height_ios = y2_ios - y1_ios;
      double width_ios = x2_ios - x1_ios;

      double height_web = y2_web - y1_web;
      double width_web = x2_web - x1_web;

      print([x1_ios, y1_ios, height_ios, width_ios]);

      context['Meteor'].callMethod('call', ['photo', session, x1_ios, y1_ios, height_ios, width_ios]);
      photoPresent = true;

       // call screenshot for multi-fidelity overlay
      if (cd.containsKey(421) && callTransperancy) {
        print('call transperancy');
        context.callMethod('screenshot', [x1_web, y1_web, width_web, height_web, x1_ios, y1_ios, width_ios, height_ios]);
        callTransperancy = false;
      }
    }
    else if (photoPresent && (!cd.containsKey(93) || !cd.containsKey(155) || !cd.containsKey(203) || !cd.containsKey(271)) ){
      print('hide photo');
      context['Meteor'].callMethod('call', ['photo', session, -999, -999, -999, -999]);
      photoPresent = false;
    }

    // <editor-fold desc="map">
    // 157 – top L; 205 – top  R; 279 – bottom L; 327 – bottom R
    if (cd.containsKey(157) && cd.containsKey(205) && cd.containsKey(279) && cd.containsKey(327)){
      print('show map');
      List<double> coordinates = fetchCoordinates(cd[157], cd[205], cd[279]);
      double x1_web = coordinates[0]; // top left
      double y1_web = coordinates[1];
      double x2_web = coordinates[2]; // top right
      double y2_web = coordinates[3]; // bottom left

      List<double> transformed = transformIos(x1_web, x2_web, y1_web, y2_web);
      double x1_ios = transformed[0];
      double x2_ios = transformed[1];
      double y1_ios = transformed[2];
      double y2_ios = transformed[3];

      double height_ios = y2_ios - y1_ios;
      double width_ios = x2_ios - x1_ios;

      double height_web = y2_web - y1_web;
      double width_web = x2_web - x1_web;

      print([x1_ios, y1_ios, height_ios, width_ios]);

      context['Meteor'].callMethod('call', ['map', session, x1_ios, y1_ios, height_ios, width_ios]);
      mapPresent = true;

       // call screenshot for multi-fidelity overlay
      if (cd.containsKey(331)) {
        context.callMethod('screenshot', [x1_web, y1_web, width_web, height_web, x1_ios, y1_ios, width_ios, height_ios]);
      }
    }
    else if (mapPresent && (!cd.containsKey(157) || !cd.containsKey(205) || !cd.containsKey(279) || !cd.containsKey(327)) ){
      print('hide map');
      context['Meteor'].callMethod('call', ['map', session, -999, -999, -999, -999]);
      mapPresent = false;
    }
    // </editor-fold>

    print(cd);
  }


}


// max x: 875 (left)
// min x: 420 (right)
// max y: 655 (bottom)
// min y: ~25 (top)
