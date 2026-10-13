# Native JNI and protobuf look up these classes/fields by name at runtime.
# https://onnxruntime.ai/docs/build/android.html#note-proguard-rules-for-r8-minimization-android-app-builds-to-work
-keep class ai.onnxruntime.** { *; }
# MediaPipe tasks/protos use reflection and native entry points.
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
