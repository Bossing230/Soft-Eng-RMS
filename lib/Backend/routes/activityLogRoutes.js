const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/activityLogController');
const authenticate = require('../middleware/auth');

// Every signed-in role may open the Activity Log. What each one sees is decided
// in the controller: administrators and managers see everyone's activity,
// everyone else only their own.
router.use(authenticate);

router.get('/kinds', ctrl.kinds); // before '/'
router.get('/', ctrl.list);

module.exports = router;