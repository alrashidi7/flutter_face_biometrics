# FaceNet Model

Place `facenet.tflite` in this folder for the package to work.

The consuming app must:
1. Add this asset to its `pubspec.yaml`:
   ```yaml
   flutter:
     assets:
       - packages/flutter_face_biometrics/assets/models/facenet.tflite
   ```
2. Or copy the model to `assets/models/facenet.tflite` in the app and reference it there.

Download the FaceNet model from:
- https://github.com/MuhammadHananAsghar/FaceNet_TFLITE
- Or similar FaceNet 128D embedding models compatible with tensorflow_face_verification.
