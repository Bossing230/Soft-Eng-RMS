const ConfigManager = require('../patterns/singletons/ConfigManager');

/**
 * Public (to any signed-in employee), read-only: the tax and service-charge
 * rates applied to every order. Lets the POS preview the total before the
 * order is actually created, instead of guessing or hardcoding the rate.
 */
exports.orderRates = (req, res) => {
  try {
    res.json({
      taxRate: ConfigManager.get('taxRate'),
      serviceChargeRate: ConfigManager.get('serviceChargeRate'),
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};