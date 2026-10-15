// The fixed set of kitchen stations the app understands. Kept in one place so
// the Kitchen board, the Menu "station" field, and the database backfill
// (ensure-menu-station.js) all agree on the same names.
module.exports = ['Grill', 'Pasta', 'Salad', 'Desserts', 'Drinks'];