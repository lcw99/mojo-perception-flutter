import 'dart:io';
import 'dart:developer';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:tflite_flutter_helper/tflite_flutter_helper.dart';

import 'image_converter.dart';

/// FaceMeshService runs predictions for anonymized landmarks
class ObjectDetectionService {
  final int inputSize = 192;

  final Logger logger = Logger("ObjectDetectionService");

  /// Tflite [Interpreter] to evaluate tflite model
  Interpreter interpreter;

  /// Shape of model's input
  late List<int> inputShape;
  late QuantizationParams inputParam;

  /// Shapes of model's outputs
  late List<List<int>> outputsShapes;

  /// Creates a FaceMeshService from [interpreter] containing tflite model
  /// to generate anonymized face landmarks.
  ///
  /// Sets [inputShape], [outputShapes] and [outputTypes] from [interpreter]
  ObjectDetectionService(this.interpreter, this.inputShape, this.inputParam, this.outputsShapes);

  /// Process given [inputImage] to prepare for feeding the model
  TensorImage getProcessedImage(TensorImage inputImage) {
    final imageProcessor = ImageProcessorBuilder()
        //.add(Rot90Op(1))
        .add(ResizeOp(inputShape[1], inputShape[2], ResizeMethod.BILINEAR))
        .add(NormalizeOp(0, 255))
        .add(QuantizeOp(inputParam.zeroPoint.toDouble(), inputParam.scale))
        .build();

    inputImage = imageProcessor.process(inputImage);
    return inputImage;
  }

  /// Predicts anonymized face landmarks from [image]
  Map<String, dynamic>? predict(img.Image image) {
    final tensorImage = TensorImage(TfLiteType.uint8);
    tensorImage.loadImage(image);

    final inputImage = getProcessedImage(tensorImage);

    TensorBuffer scores = TensorBufferFloat(outputsShapes[0]);
    TensorBuffer boxes = TensorBufferFloat(outputsShapes[1]);
    TensorBuffer count = TensorBufferFloat(outputsShapes[2]);
    TensorBuffer classes = TensorBufferFloat(outputsShapes[3]);

    final inputs = <Object>[Uint8List.fromList(inputImage.getTensorBuffer().getIntList())];
    //final inputs = <Object>[Uint8List(442368)];

    final outputs = <int, Object>{
      0: scores.buffer,
      1: boxes.buffer,
      2: count.buffer,
      3: classes.buffer,
    };

    interpreter.runForMultipleInputs(inputs, outputs);

    final scoreList = scores.getDoubleList();
    final numDetection = count.getDoubleValue(0).toInt();
    final boundingBox = boxes.getDoubleList();
    final classID = classes.getDoubleList();

    int maxIndex = -1;
    double maxValue = -1;
    for (int i = 0; i < numDetection; i++) {
      if (scoreList[i] > maxValue) {
        maxValue = scoreList[i];
        maxIndex = i;
      }
    }
    double b0 = boundingBox[maxIndex * 4];
    double b1 = boundingBox[maxIndex * 4 + 1];
    double b2 = boundingBox[maxIndex * 4 + 2];
    double b3 = boundingBox[maxIndex * 4 + 3];
    b0 = b0 < 0 ? 0 : b0;
    b1 = b1 < 0 ? 0 : b1;
    b2 = b2 < 0 ? 0 : b2;
    b3 = b3 < 0 ? 0 : b3;
    double yMin = b0 * image.height;
    double xMin = b1 * image.width;
    double yMax = b2 * image.height;
    double xMax = b3 * image.width;

    List<double> objectResult = [];
    if (maxIndex >= 0) {
      if (maxValue >= 0.25) {
        log('score=' + maxValue.toString(), name: 'lcw');
        log('rect=$b0, $b1, $b2, $b3', name: 'lcw');
        log('rect=$xMin, $yMin, $xMax, $yMax', name: 'lcw');
        objectResult.add(maxValue);
        objectResult.add(xMin);
        objectResult.add(yMin);
        objectResult.add(xMax);
        objectResult.add(yMax);
      }
    }
    return {'object': objectResult};
  }
}

/// Function called by [Isolate] to process [image]
/// and predict anonymized face landmarks

Map<String, dynamic>? runObjectDetect(Map<String, dynamic> params) {
  final objectDetection = ObjectDetectionService(
      Interpreter.fromAddress(params['detectorAddress']),
      params["inputShape"],
      params["inputParam"],
      params["outputsShapes"]);
  //final image = ImageConverter.convertCameraImage(params['cameraImage'])!;
  //image_lib.Image? testImage = params['testImage'];
  img.Image? testImage = null;
  Map<String, dynamic>? result;
  if (testImage != null) {
    result = objectDetection.predict(testImage);
    return result;
  }

/*
  var image = ImageConverter.convertCameraImage(params['cameraImage'])!;
  if (Platform.isAndroid) {
    image = img.copyRotate(image, -90);
    image = img.flipHorizontal(image);
  }
*/
  var image = params['cameraImage'];
  result = objectDetection.predict(image);

  return result;
}
