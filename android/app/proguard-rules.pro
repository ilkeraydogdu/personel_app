# Flutter Obfuscation & Security ProGuard Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Anti-Reverse Engineering & Hardening
-dontusemixedcaseclassnames
-dontskipnonpubliclibraryclasses

# Keep Parcelable and Serializable
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Play Core & Flutter Embedding suppressions for R8
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.**

# HomeWidget & AppWidget Providers
-keep class es.antonborri.home_widget.** { *; }
-keep class * extends android.appwidget.AppWidgetProvider { *; }
