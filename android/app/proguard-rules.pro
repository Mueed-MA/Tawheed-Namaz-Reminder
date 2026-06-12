# Keep generic type signatures required by Gson TypeToken.
-keepattributes Signature
-keepattributes *Annotation*

# Keep Gson reflection classes used by flutter_local_notifications cache parsing.
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.google.gson.** { *; }

# Keep flutter_local_notifications model classes serialized/deserialized via Gson.
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }

# Keep flutter_local_notifications runtime components (receivers, services).
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Keep Firebase Messaging plugin classes used by background handlers.
-keep class io.flutter.plugins.firebase.messaging.** { *; }
-keep class com.google.firebase.messaging.** { *; }
