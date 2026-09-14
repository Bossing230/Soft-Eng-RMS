/**
 * Singleton Pattern — holds restaurant/system-wide configuration
 * (tax rate, service charge, restaurant info) loaded once and shared.
 */
class ConfigManager {
  constructor() {
    if (ConfigManager.instance) {
      return ConfigManager.instance;
    }

    this.settings = {
      restaurantName: process.env.RESTAURANT_NAME || 'My Restaurant',
      taxRate: parseFloat(process.env.TAX_RATE || '0.12'),
      serviceChargeRate: parseFloat(process.env.SERVICE_CHARGE_RATE || '0.10'),
      currency: process.env.CURRENCY || 'PHP',
    };

    ConfigManager.instance = this;
  }

  get(key) {
    return this.settings[key];
  }

  set(key, value) {
    this.settings[key] = value;
    return this.settings;
  }

  getAll() {
    return { ...this.settings };
  }
}

module.exports = new ConfigManager();