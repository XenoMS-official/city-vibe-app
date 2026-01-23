const functions = require("firebase-functions");
const admin = require("firebase-admin");

const stripeSecretKey = process.env.STRIPE_SECRET_KEY;


admin.initializeApp();

exports.createPaymentIntent = functions.https.onCall(async (data, context) => {
  // 1. Logging to debug what we receive
  console.log("Received data:", data);

  // 2. Robust extraction of parameters
  // Sometimes data is nested in 'data' key depending on SDK version
  const amount = data.amount || (data.data && data.data.amount);
  const currency = data.currency || (data.data && data.data.currency);

  // 3. Validation
  if (!amount || !currency) {
    throw new functions.https.HttpsError(
      'invalid-argument', 
      'The function must be called with "amount" and "currency".'
    );
  }

  try {
    // 4. Create Payment Intent
    const paymentIntent = await stripe.paymentIntents.create({
      amount: parseInt(amount), // Ensure it's an integer
      currency: currency,
      payment_method_types: ["card"],
    });

    return {
      clientSecret: paymentIntent.client_secret,
    };
  } catch (error) {
    console.error("Stripe Error:", error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});