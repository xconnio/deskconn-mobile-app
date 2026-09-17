-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

-keep class id.flutter.flutter_background_service.** { *; }
-keep class com.dexterous.** { *; }
-keep class com.baseflow.** { *; }

-keepattributes *Annotation*
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable

-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**
