import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as UI;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:mojo_perception/mojo_perception.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';
import 'package:image/image.dart' as img;
import 'package:google_fonts/google_fonts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(CameraApp());
}

class CameraApp extends StatefulWidget {
  MojoPerceptionAPI mojoPerceptionApi =
      MojoPerceptionAPI('<auth_token>', '<host>', '<port>', '<user_namespace>');

  CameraApp() {
    mojoPerceptionApi.setOptions({
      "emotions": ["amusement"],
      "subscribeRealtimeOutput": true
    });
  }

  @override
  State<CameraApp> createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> {
  bool isStopped = false;
  bool isRunning = false;

  void stopCallback() {
    setState(() {
      isStopped = true;
    });
  }

  void errorCallback(error) {
    if (kDebugMode) {
      print("🔴 $error");
    }
  }

  @override
  void dispose() {
    super.dispose();
    widget.mojoPerceptionApi.stopFacialExpressionRecognitionAPI();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.mojoPerceptionApi.onStopCallback = stopCallback;
      widget.mojoPerceptionApi.onErrorCallback = errorCallback;
    });
  }

  @override
  Widget build(BuildContext context) {
    GlobalKey<FaceWidgetState> faceWidgetKey = GlobalKey();

    return MaterialApp(
      home: Scaffold(
        floatingActionButton: FloatingActionButton(
            child: const Icon(Icons.camera),
            backgroundColor: Colors.green,
            onPressed: () async {
              widget.mojoPerceptionApi.controlInference(false);
              if (!await Permission.storage.isGranted) {
                await Permission.storage.request();
              }
              Uint8List imageBytes = await faceWidgetKey.currentState!.capturePng();
              var result = await ImageGallerySaver.saveImage(imageBytes);
              log('image save result=' + result.toString(), name: 'lcw');

              Uint8List? lastTestedImageBytes = faceWidgetKey.currentState!.getLastTestedImage();
              if (lastTestedImageBytes != null) {
                result = await ImageGallerySaver.saveImage(lastTestedImageBytes);
                log('image save result=' + result.toString(), name: 'lcw');
              }
              Future.delayed(const Duration(seconds: 2), () {
                widget.mojoPerceptionApi.controlInference(true);
              });
            }
        ),
        body: isStopped
            ? const Center(child: Text("Session ended"))
            : !isRunning
            ? Center(child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    isRunning = true;
                  });
                },
                icon: const Icon(
                  Icons.run_circle,
                  size: 50.0,
                ),
                label: const Text('Run'),
            ))
            : FutureBuilder<CameraController?>(
                future: widget.mojoPerceptionApi.startCameraAndConnectAPI(),
                builder: (BuildContext context,
                    AsyncSnapshot<CameraController?> snapshot) {
                  if (snapshot.hasData) {
                    final mediaSize = MediaQuery.of(context).size;
                    final scale = 1 / (widget.mojoPerceptionApi.cameraController!.value.aspectRatio * MediaQuery.of(context).size.aspectRatio);
                    FaceWidget faceWidget = FaceWidget(widget.mojoPerceptionApi, scale, key: faceWidgetKey);
                    return Stack(
                        children: [
                          ClipRect(
                          clipper: _MediaSizeClipper(mediaSize),
                          child: Transform.scale(
                            scale: scale,
                            alignment: Alignment.topLeft,
                            child: CameraPreview(widget.mojoPerceptionApi.cameraController!))),
                          faceWidget,
                          //AmusementWidget(widget.mojoPerceptionApi)
                        ],
                      );
                  } else {
                    return Container();
                  }
                }),
      ),
    );
  }
}

class _MediaSizeClipper extends CustomClipper<Rect> {
  final Size mediaSize;
  const _MediaSizeClipper(this.mediaSize);
  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, mediaSize.width, mediaSize.height);
  }
  @override
  bool shouldReclip(CustomClipper<Rect> oldClipper) {
    return true;
  }
}

class FaceWidget extends StatefulWidget {
  final MojoPerceptionAPI mojoPerceptionApi;
  final double scale;
  const FaceWidget(this.mojoPerceptionApi, this.scale, {Key? key}) : super(key: key);
  @override
  FaceWidgetState createState() => FaceWidgetState();
}

class FaceWidgetState extends State<FaceWidget> {
  late double _ratio;

  GlobalKey facePaintKey = GlobalKey();

  Future<Uint8List> capturePng() async {
    RenderRepaintBoundary boundary = facePaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary;
    UI.Image image = await boundary.toImage();
    ByteData? byteData = await image.toByteData(format: UI.ImageByteFormat.png);
    Uint8List pngBytes = byteData!.buffer.asUint8List();
    return pngBytes;
  }

  Uint8List? getLastTestedImage() {
    return testedImage;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.mojoPerceptionApi.faceDetectedCallback = myCallback);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.mojoPerceptionApi.facemeshDetectedCallback = facemeshCallback);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.mojoPerceptionApi.objectDetectedCallback = objectCallback);
  }

  Rect? face;
  void myCallback(newFace) {
    setState(() {
      face = newFace;
    });
  }

  List<double>? object;
  void objectCallback(newObject) {
    setState(() {
      object = newObject;
    });
  }

  List<List<double>>? facemesh;
  Uint8List? testedImage;
  UI.Image? testedImageUI;
  Offset? topLeft;
  void facemeshCallback(newFacemesh, img.Image croppedImage, offset) {
    testedImage = Uint8List.fromList(img.JpegEncoder().encodeImage(croppedImage));
    img.Image resizedImage = img.copyResize(croppedImage, width: (croppedImage.width * _ratio).toInt());
    loadUiImage(resizedImage).then((image) => setState(() {
      topLeft = offset;
      facemesh = newFacemesh;
      testedImageUI = image;
    }));
  }

  Future<UI.Image> loadUiImage(img.Image img1) async {
    final Completer<UI.Image> completer = Completer();
    UI.decodeImageFromList(Uint8List.fromList(img.JpegEncoder().encodeImage(img1)), (UI.Image img2) {
      return completer.complete(img2);
    });
    return completer.future;
  }

  bool showCroppedImage = true;
  @override
  Widget build(BuildContext context) {
    var screenSize = MediaQuery.of(context).size;
    _ratio = screenSize.width / widget.mojoPerceptionApi.cameraController!.value.previewSize!.height * widget.scale;
    return Stack(children: [
      face != null ? RepaintBoundary(key: facePaintKey,
          child: SizedBox(
              width: screenSize.width, height: screenSize.height,
              child: CustomPaint(painter: FacemeshPainter(facemesh, _ratio, testedImageUI, topLeft, showCroppedImage))
          )
      ) : const SizedBox(),
      face != null ? CustomPaint(painter: FaceDetectionPainter(face!, _ratio)) : const SizedBox(),
      object != null ? CustomPaint(painter: ObjectDetectionPainter(object!, _ratio),
          size: Size(screenSize.width, screenSize.height)) : const SizedBox(),
    ]);
  }
}

class FaceDetectionPainter extends CustomPainter {
  final Rect bbox;
  final double ratio;

  FaceDetectionPainter(
    this.bbox,
    this.ratio,
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (bbox != Rect.zero) {
      var paint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      Offset topLeft = bbox.topLeft * ratio;
      Offset bottomRight = bbox.bottomRight * ratio;
      canvas.drawRect(Rect.fromPoints(topLeft, bottomRight), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class ObjectDetectionPainter extends CustomPainter {
  final List<double> object;
  final double ratio;

  ObjectDetectionPainter(
      this.object,
      this.ratio,
      );

  @override
  void paint(Canvas canvas, Size size) {
    if (object.length == 5) {
      var paint = Paint()
        ..color = Colors.yellowAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      Rect bbox = Rect.fromLTRB(object[1], object[2], object[3], object[4]);
      Offset topLeft = bbox.topLeft * ratio;
      Offset bottomRight = bbox.bottomRight * ratio;
      canvas.drawRect(Rect.fromPoints(topLeft, bottomRight), paint);
      drawText(canvas, Offset(10, size.height - 20), '카드:' + (object[0] * 100).toStringAsFixed(2), 15);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

void drawText(Canvas canvas, Offset offset, String text, double size, {color = Colors.yellowAccent}) {
/*
    var textStyle = TextStyle(
      fontFeatures: const [UI.FontFeature.tabularFigures()],
      color: Colors.black,
      fontSize: size,
    );
*/
  var textStyle = GoogleFonts.getFont('Nanum Gothic Coding').copyWith(
      fontSize: size,
      color: color,
      backgroundColor: Colors.black87);
  final textSpan = TextSpan(
    text: text,
    style: textStyle,
  );
  final textPainter = TextPainter(
    text: textSpan,
    textDirection: TextDirection.ltr,
  );
  textPainter.layout();
  textPainter.paint(canvas, offset);
}

class FacemeshPainter extends CustomPainter {
  final List<List<double>>? facemesh;
  final double ratio;
  final UI.Image? testedImage;
  final Offset? topLeft;
  final bool showImage;

  FacemeshPainter(
      this.facemesh,
      this.ratio,
      this.testedImage,
      this.topLeft,
      this.showImage,
      );

  @override
  void paint(Canvas canvas, Size size) {
    if(topLeft == null) {
      return;
    }
    double ratio1 = ratio;
    Offset topLeft1 = topLeft! * ratio1;
    List<int> leftEye = [384, 385, 386, 387, 388, 390, 263, 362, 398, 466, 373, 374, 249, 380, 381, 382];
    List<int> rightEye = [160, 33, 161, 163, 133, 7, 173, 144, 145, 246, 153, 154, 155, 157, 158, 159];
    List<int> faceOval = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109, 10];
    List<int> centerLine = [0, 4, 8, 0];

    if (facemesh != null) {
      var paint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round;

      if (testedImage != null && showImage) {
        canvas.drawImage(testedImage!, topLeft1, paint);
      }

      List<Offset> landmarks = [];
      for (int i = 0; i < 468; i++) {
        List<double> lm = facemesh![i];
        Offset o = Offset(lm[0], lm[1]) * ratio1 + topLeft1;
        landmarks.add(o);
        //drawText(canvas, o, i.toString(), 6);
      }
      //canvas.drawPoints(UI.PointMode.points, landmarks, paint);

      List<Offset> mesh = [];
      for (int i in leftEye) {
        List<double> lm = facemesh![i];
        Offset o = Offset(lm[0], lm[1]) * ratio1 + topLeft1;
        mesh.add(o);
        //drawText(canvas, o, i.toString(), 6);
      }
      //canvas.drawPoints(UI.PointMode.points, mesh, paint);

      mesh = [];
      for (int i in rightEye) {
        List<double> lm = facemesh![i];
        Offset o = Offset(lm[0], lm[1]) * ratio1 + topLeft1;
        mesh.add(o);
        //drawText(canvas, o, i.toString(), 6);
      }
      //canvas.drawPoints(UI.PointMode.points, mesh, paint);

      paint.color = Colors.yellowAccent;
      List<Offset> leftIris = [];
      for (int i = 0; i < 5; i++) {
        List<double> lm = facemesh![468 + i];
        Offset o = Offset(lm[0], lm[1]) * ratio1 + topLeft1;
        leftIris.add(o);
        //drawText(canvas, o, i.toString(), 4, color: Colors.black);
      }
      List<Offset> rightIris = [];
      for (int i = 0; i < 5; i++) {
        List<double> lm = facemesh![468 + 5 + i];
        rightIris.add(Offset(lm[0], lm[1]) * ratio1 + topLeft1);
      }
      canvas.drawPoints(UI.PointMode.points, leftIris, paint);
      canvas.drawPoints(UI.PointMode.points, rightIris, paint);

      paint.color = Colors.white70;
      List<Offset> faceOvalPoly = [];
      for (int i in faceOval) {
        List<double> lm = facemesh![i];
        Offset o = Offset(lm[0], lm[1]) * ratio1 + topLeft1;
        faceOvalPoly.add(o);
        //drawText(canvas, o, i.toString(), 5, color: Colors.blue);
      }
      canvas.drawPoints(UI.PointMode.polygon, faceOvalPoly, paint);

      List<Offset> centerTriangle = [];
      for (int i in centerLine) {
        List<double> lm = facemesh![i];
        Offset o = Offset(lm[0], lm[1]) * ratio1 + topLeft1;
        centerTriangle.add(o);
      }
      canvas.drawPoints(UI.PointMode.polygon, centerTriangle, paint);

      canvas.drawLine(leftIris[0], rightIris[0], paint);

      double leftIrisSize = (leftIris[1] - leftIris[3]).distance;
      double rightIrisSize = (rightIris[1] - rightIris[3]).distance;
      double irisSize = (leftIrisSize + rightIrisSize) / 2;
      double realSizeRatio = 1170 / irisSize;

      double y = 40;
      double irisDistance =(leftIris[0] - rightIris[0]).distance * realSizeRatio / 100;
      drawText(canvas, Offset(10, y), '동공:' + irisDistance.toStringAsFixed(2), 15);
      y += 17;

      double verticalTilt = facemesh![151][0] - facemesh![200][0];
      drawText(canvas, Offset(10, y), '세로기울기:' + verticalTilt.toStringAsFixed(2), 15);
      y += 17;

      double verticalLength = (landmarks[10] - landmarks[152]).distance * realSizeRatio / 100;
      drawText(canvas, Offset(10, y), '길이:' + verticalLength.toStringAsFixed(2), 15);
      y += 17;

      double horizontalLength = (landmarks[127] - landmarks[356]).distance * realSizeRatio / 100;
      drawText(canvas, Offset(10, y), '너비:' + horizontalLength.toStringAsFixed(2), 15);
      y += 17;

      double faceRate = verticalLength / horizontalLength * 100;
      drawText(canvas, Offset(10, y), '비율:' + faceRate.toStringAsFixed(2), 15);
      y += 17;

      double migan = (landmarks[362].dx - landmarks[133].dx) * realSizeRatio / 100;
      drawText(canvas, Offset(10, y), '미간:' + migan.toStringAsFixed(2), 15);
      y += 17;

      faceOvalPoly = faceOvalPoly.map((e) => e * realSizeRatio).toList();
      double faceArea = getArea(faceOvalPoly) / 10000;
      drawText(canvas, Offset(10, y), '면적:' + faceArea.toStringAsFixed(2), 15);
      y += 17;
    }
  }

  double getArea(List<Offset> poly) {
/*
    double area = 0;
    int n = poly.length;
    if (n.isOdd) {
      poly.add(poly[0]);
      n = poly.length;
    }
    for(int i = 0; i < n - 2; i += 2) {
      area += poly[i+1].dx * (poly[i+2].dy - poly[i].dy) + poly[i+1].dy * (poly[i].dx - poly[i+2].dx);
    }
    area /= 2;
    return area;
*/

    int n = poly.length;
    double area = 0.0;
    for (int i = 0; i < n; i++) {
      int j = (i + 1) % n;
      area += poly[i].dx * poly[j].dy;
      area -= poly[j].dx * poly[i].dy;
    }
    area = area.abs() / 2.0;
    return area;
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class AmusementWidget extends StatefulWidget {
  MojoPerceptionAPI mojoPerceptionApi;
  AmusementWidget(this.mojoPerceptionApi);
  @override
  _AmusementWidgetState createState() => _AmusementWidgetState();
}

class _AmusementWidgetState extends State<AmusementWidget> {
  double amusementValue = 0;
  Color amusementColor = Colors.red;
  String amusementIcon = "😒";

  void amusementCallback(double data) {
    setState(() {
      amusementValue = data;
      if (amusementValue > 0.75) {
        amusementColor = Colors.green;
        amusementIcon = "😂";
      } else if (amusementValue < 0.25) {
        amusementColor = Colors.red;
        amusementIcon = "😄";
      } else {
        amusementColor = Colors.orange;
        amusementIcon = "😒";
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.mojoPerceptionApi.amusementCallback = amusementCallback);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      child: Row(
        children: [
          SfSliderTheme(
            data: SfSliderThemeData(
                thumbColor: Colors.white,
                thumbRadius: 15,
                thumbStrokeWidth: 2,
                thumbStrokeColor: amusementColor),
            child: SfSlider.vertical(
              activeColor: amusementColor,
              inactiveColor: Colors.grey,
              min: 0.0,
              max: 1,
              value: amusementValue,
              interval: 5,
              enableTooltip: true,
              minorTicksPerInterval: 2,
              thumbIcon: Center(
                  child: Text(
                amusementIcon,
                style: const TextStyle(fontSize: 20),
              )),
              onChanged: (dynamic value) {},
            ),
          ),
          Text(
            amusementValue.toStringAsFixed(2),
            style: TextStyle(fontSize: 30, color: amusementColor),
          )
        ],
      ),
    );
  }
}
