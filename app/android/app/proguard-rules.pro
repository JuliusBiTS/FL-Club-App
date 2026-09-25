# R8 (the release-build shrinker) keep/ignore rules.

# flutter_stripe's bridge code refers to Stripe's "push provisioning" classes,
# which the Stripe Android SDK doesn't include (we don't add cards to Google
# Wallet from inside the app). Without this rule the release build stops with
# "R8: Missing class com.stripe.android.pushProvisioning.PushProvisioningActivity$f".
-dontwarn com.stripe.android.pushProvisioning.**

# The QR scanner (mobile_scanner + Google ML Kit barcode scanning). Without
# these, R8 strips ML Kit's BarcodeScanning class from the release build and
# the camera fails to start with "The camera couldn't start". Found by reading
# build/app/outputs/mapping/release/usage.txt: BarcodeScanning was REMOVED.
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.libraries.barhopper.** { *; }
-dontwarn com.google.mlkit.**
