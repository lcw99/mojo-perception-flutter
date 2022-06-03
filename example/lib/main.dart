import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mojo_perception/mojo_perception.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';

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
    return MaterialApp(
      home: Scaffold(
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
                    return Center(
                      child: Stack(
                        children: [
                          CameraPreview(
                              widget.mojoPerceptionApi.cameraController!),
                          FaceWidget(widget.mojoPerceptionApi),
                          //AmusementWidget(widget.mojoPerceptionApi)
                        ],
                      ),
                    );
                  } else {
                    return Container();
                  }
                }),
      ),
    );
  }
}

class FaceWidget extends StatefulWidget {
  MojoPerceptionAPI mojoPerceptionApi;
  FaceWidget(this.mojoPerceptionApi);
  @override
  _FaceWidgetState createState() => _FaceWidgetState();
}

class _FaceWidgetState extends State<FaceWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.mojoPerceptionApi.faceDetectedCallback = myCallback);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.mojoPerceptionApi.facemeshDetectedCallback = facemeshCallback);
  }

  Rect? face;
  void myCallback(newface) {
    setState(() {
      face = newface;
    });
  }

  List<List<double>>? facemesh;
  void facemeshCallback(newFacemesh) {
    setState(() {
      facemesh = newFacemesh;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    double _ratio = screenSize.width /
        widget.mojoPerceptionApi.cameraController!.value.previewSize!.height;
    return face != null
        ? Stack(children: [
            CustomPaint(painter: FaceDetectionPainter(face!, _ratio)),
            CustomPaint(painter: FacemeshPainter(facemesh, _ratio)),
          ])
        : Container();
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

      Offset topleft = bbox.topLeft * ratio;
      Offset bottomright = bbox.bottomRight * ratio;
      canvas.drawRect(Rect.fromPoints(topleft, bottomright), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class FacemeshPainter extends CustomPainter {
  final List<List<double>>? facemesh;
  final double ratio;

  FacemeshPainter(
      this.facemesh,
      this.ratio,
      );

  @override
  void paint(Canvas canvas, Size size) {
    List<int> leftEye = [384, 385, 386, 387, 388, 390, 263, 362, 398, 466, 373, 374, 249, 380, 381, 382];
    List<int> rightEye = [160, 33, 161, 163, 133, 7, 173, 144, 145, 246, 153, 154, 155, 157, 158, 159];
    if (facemesh != null) {
      var paint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      List<Offset> mesh = [];
      for (int i in leftEye) {
        List<double> lm = facemesh![i];
        mesh.add(Offset(lm[0], lm[1]) * ratio);
      }
      canvas.drawPoints(PointMode.points, mesh, paint);

      mesh = [];
      for (int i in rightEye) {
        List<double> lm = facemesh![i];
        mesh.add(Offset(lm[0], lm[1]) * ratio);
      }
      canvas.drawPoints(PointMode.points, mesh, paint);

      paint.color = Colors.yellow;
      List<Offset> leftIris = [];
      for (int i = 0; i < 5; i++) {
        List<double> lm = facemesh![468 + i];
        leftIris.add(Offset(lm[0], lm[1]) * ratio);
      }
      List<Offset> rightIris = [];
      for (int i = 0; i < 5; i++) {
        List<double> lm = facemesh![468 + 5 + i];
        rightIris.add(Offset(lm[0], lm[1]) * ratio);
      }
      canvas.drawPoints(PointMode.points, leftIris, paint);
      canvas.drawPoints(PointMode.points, rightIris, paint);

      canvas.drawLine(leftIris[0], rightIris[0], paint);
    }
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
