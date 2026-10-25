const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/accountController');
const authenticate = require('../middleware/auth');
const upload = require('../middleware/upload');

// Every signed-in role manages its OWN account here. Nothing in these routes
// takes an employee id from the request: the account is always the one in the
// login token, so nobody can edit someone else's profile through them.
router.use(authenticate);

/** Runs the photo upload and turns upload errors into a clear 400 instead of a server error. */
function uploadImage(req, res, next) {
  upload.single('image')(req, res, (err) => {
    if (!err) return next();
    const tooBig = err.code === 'LIMIT_FILE_SIZE';
    res.status(400).json({
      error: tooBig ? 'That photo is too large. Choose one under 5 MB.' : err.message || 'Could not upload the photo',
    });
  });
}

router.get('/profile', ctrl.getProfile);
router.put('/profile', ctrl.updateProfile);
router.post('/photo', uploadImage, ctrl.uploadPhoto);
// POST (not DELETE) because the password has to travel in the request body.
router.post('/delete', ctrl.deleteAccount);

module.exports = router;