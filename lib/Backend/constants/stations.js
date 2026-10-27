// The fixed set of kitchen stations the app understands. Kept in one place so
// the Kitchen board, the Menu "station" field, and the database backfill
// (ensure-menu-station.js) all agree on the same names.
//
// Drinks and Counter are for items that are not cooked: Drinks for bottles and
// cups, Counter for packaged items such as chips or bottled water that just
// get handed over. They are the stations that don't decide where a mixed order
// shows up on the Kitchen board (see dominantStation in orderController.js).
module.exports = ['Grill', 'Pasta', 'Salad', 'Desserts', 'Drinks', 'Counter'];