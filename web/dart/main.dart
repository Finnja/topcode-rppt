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
import 'dart:convert';
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
  bool blockPresent = false;

  
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


    // grab a bitmap from the canvas
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
      double radius = cd[93][1];

      // top left
      double x1 = cd[93][2] + radius;
      double y1 = cd[93][3] - radius;

      // top right
      double x2 = cd[155][2] + radius;

      // bottom left
      double y2 = cd[203][3] - radius; 

      // coordinate transforms
      x1 = (892 - x1) * (375/455);
      x2 = (892 - x2) * (375/455);
      y1 = (y1 - 20) * (667 / 650);
      y2 = (y2 - 20) * (667 / 650);

      double height = y2 - y1;
      double width = x2 - x1;

      print([x1, y1, height, width]);

      context['Meteor'].callMethod('call', ['photo', session, x1, y1, height, width]);
      photoPresent = true;

       // call screenshot for multi-fidelity overlay
      if (cd.containsKey(421)) {
        context.callMethod('screenshot', [x1, y1, height, width]);
      }
    }
    else if (photoPresent && (!cd.containsKey(93) || !cd.containsKey(155) || !cd.containsKey(203) || !cd.containsKey(271)) ){
      print('hide photo');
      context['Meteor'].callMethod('call', ['photo', session, -999, -999, -999, -999]);
      photoPresent = false;
    }

    // // send block
    // if (cd.containsKey(93) && !blockPresent){
    //   print('show block');
    //   int x = cd[93][2];
    //   int y = cd[93][3];
    //   int radius = cd[93][1];
    //   context['Meteor'].callMethod('call', ['block', session, x, y, radius]);
    //   blockPresent = true;
    // }
    // else if (blockPresent && !cd.containsKey(93)){
    //   print('hide block');
    //   context['Meteor'].callMethod('call', ['block', session, -999, -999]);
    //   blockPresent = true;
    // }


    print(cd);
  }


}


// max x: 875 (left)
// min x: 420 (right)
// max y: 655 (bottom)
// min y: ~25 (top)