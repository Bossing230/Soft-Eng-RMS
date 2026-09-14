/**
 * Strategy Pattern — each payment method implements a common
 * `process(order, payload)` interface so the controller doesn't
 * need to know the details of any one payment method.
 */

const axios = require('axios');

class PaymentStrategy {
  async process(order, payload) {
    throw new Error('process() must be implemented by a subclass');
  }
}

class CashPaymentStrategy extends PaymentStrategy {
  async process(order, payload) {
    const { cashReceived } = payload;
    if (cashReceived < order.total_amount) {
      throw new Error('Cash received is less than the total amount');
    }
    return {
      method: 'cash',
      status: 'paid',
      amount: order.total_amount,
      change: +(cashReceived - order.total_amount).toFixed(2),
      transactionReference: `CASH-${Date.now()}`,
    };
  }
}

class CardPaymentStrategy extends PaymentStrategy {
  async process(order, payload) {
    // Placeholder for a real card terminal / gateway integration.
    if (!payload.cardToken) {
      throw new Error('Missing card token');
    }
    return {
      method: 'card',
      status: 'paid',
      amount: order.total_amount,
      transactionReference: `CARD-${Date.now()}`,
    };
  }
}

class EWalletPaymentStrategy extends PaymentStrategy {
  /**
   * Integrates with PayMongo for GCash/GrabPay/Maya style e-wallet
   * and online payments. Requires PAYMONGO_SECRET_KEY in .env.
   */
  async process(order, payload) {
    const secretKey = process.env.PAYMONGO_SECRET_KEY;
    if (!secretKey) {
      throw new Error('PayMongo is not configured (missing PAYMONGO_SECRET_KEY)');
    }

    const auth = Buffer.from(`${secretKey}:`).toString('base64');
    const response = await axios.post(
      'https://api.paymongo.com/v1/sources',
      {
        data: {
          attributes: {
            amount: Math.round(order.total_amount * 100), // centavos
            redirect: {
              success: payload.successUrl || 'https://example.com/success',
              failed: payload.failedUrl || 'https://example.com/failed',
            },
            type: payload.channel || 'gcash',
            currency: 'PHP',
          },
        },
      },
      { headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/json' } }
    );

    const source = response.data.data;
    return {
      method: 'ewallet',
      status: 'pending',
      amount: order.total_amount,
      transactionReference: source.id,
      checkoutUrl: source.attributes.redirect.checkout_url,
    };
  }
}

class PaymentContext {
  static STRATEGIES = {
    cash: new CashPaymentStrategy(),
    card: new CardPaymentStrategy(),
    ewallet: new EWalletPaymentStrategy(),
    online: new EWalletPaymentStrategy(),
  };

  static getStrategy(method) {
    const strategy = PaymentContext.STRATEGIES[method];
    if (!strategy) {
      throw new Error(`Unsupported payment method: ${method}`);
    }
    return strategy;
  }
}

module.exports = { PaymentContext, CashPaymentStrategy, CardPaymentStrategy, EWalletPaymentStrategy };