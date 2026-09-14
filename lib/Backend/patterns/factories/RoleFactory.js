/**
 * Factory Pattern — centralizes creation of role-specific employee
 * records so that role-dependent defaults/validation live in one place.
 */
class Employee {
  constructor({ name, username, email, passwordHash, roleName }) {
    this.name = name;
    this.username = username;
    this.email = email;
    this.password = passwordHash;
    this.roleName = roleName;
    this.status = 'active';
  }
}

class Administrator extends Employee {
  constructor(data) {
    super({ ...data, roleName: 'administrator' });
    this.permissions = 'all';
  }
}

class Manager extends Employee {
  constructor(data) {
    super({ ...data, roleName: 'manager' });
    this.permissions = ['manage_menu', 'manage_inventory', 'manage_reservations', 'manage_orders', 'view_reports'];
  }
}

class Cashier extends Employee {
  constructor(data) {
    super({ ...data, roleName: 'cashier' });
    this.permissions = ['manage_reservations', 'manage_orders', 'process_payments'];
  }
}

class KitchenStaff extends Employee {
  constructor(data) {
    super({ ...data, roleName: 'kitchen' });
    this.permissions = ['view_kitchen_orders', 'update_order_status'];
  }
}

class RoleFactory {
  static ROLE_MAP = {
    administrator: Administrator,
    manager: Manager,
    cashier: Cashier,
    kitchen: KitchenStaff,
  };

  static create(roleName, data) {
    const RoleClass = RoleFactory.ROLE_MAP[roleName];
    if (!RoleClass) {
      throw new Error(`Unknown role: ${roleName}`);
    }
    return new RoleClass(data);
  }

  static validRoles() {
    return Object.keys(RoleFactory.ROLE_MAP);
  }
}

module.exports = RoleFactory;