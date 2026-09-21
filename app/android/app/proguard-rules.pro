# R8 (the release-build shrinker) keep/ignore rules.

# flutter_stripe's bridge code refers to Stripe's "push provisioning" classes,
# which the Stripe Android SDK doesn't include (we don't add cards to Google
# Wallet from inside the app). Without this rule the release build stops with
# "R8: Missing class com.stripe.android.pushProvisioning.PushProvisioningActivity$f".
-dontwarn com.stripe.android.pushProvisioning.**
