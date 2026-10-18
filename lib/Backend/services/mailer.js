/**
 * Sends the password-reset code by email.
 *
 * Needs the `nodemailer` package: run `npm install nodemailer` in lib/Backend
 * if it isn't already in package.json.
 *
 * Configure with these environment variables (Gmail shown; any SMTP provider
 * works the same way — change EMAIL_HOST/EMAIL_PORT/EMAIL_SECURE instead):
 *   EMAIL_USER            the sending Gmail address, e.g. rms.noreply@gmail.com
 *   EMAIL_APP_PASSWORD    a Gmail "App Password" — NOT the normal account
 *                          password, Gmail blocks that for apps. Create one at
 *                          https://myaccount.google.com/apppasswords (needs
 *                          2-Step Verification turned on first).
 *   EMAIL_FROM             optional display name, defaults to EMAIL_USER
 *
 * If EMAIL_USER / EMAIL_APP_PASSWORD aren't set, this falls back to printing
 * the code to the server console instead of failing outright — useful for
 * local development, but reset codes won't actually reach anyone's inbox
 * until real credentials are configured.
 */

let transporter = null;

function getTransporter() {
  if (transporter) return transporter;
  if (!process.env.EMAIL_USER || !process.env.EMAIL_APP_PASSWORD) return null;

  const nodemailer = require('nodemailer');
  transporter = nodemailer.createTransport({
    host: process.env.EMAIL_HOST || 'smtp.gmail.com',
    port: Number(process.env.EMAIL_PORT) || 465,
    secure: process.env.EMAIL_SECURE !== 'false', // true for port 465
    auth: { user: process.env.EMAIL_USER, pass: process.env.EMAIL_APP_PASSWORD },
  });
  return transporter;
}

/** "jose.delacruz@gmail.com" -> "jo**@gmail.com" — shown to the user instead of the full address. */
function maskEmail(email) {
  const [local, domain] = String(email).split('@');
  if (!domain) return email;
  const visible = local.slice(0, Math.min(2, local.length));
  return `${visible}${'*'.repeat(Math.max(2, local.length - visible.length))}@${domain}`;
}

async function sendResetCode({ to, name, code }) {
  const mail = getTransporter();
  const subject = 'Your Restaurant Management System password reset code';
  const text = `Hi ${name},\n\nYour password reset code is: ${code}\n\nThis code expires in 10 minutes. If you didn't request this, you can ignore this email.`;
  const html = `
    <p>Hi ${name},</p>
    <p>Your password reset code is:</p>
    <p style="font-size: 28px; font-weight: bold; letter-spacing: 4px;">${code}</p>
    <p>This code expires in 10 minutes. If you didn't request this, you can ignore this email.</p>
  `;

  if (!mail) {
    console.warn(
      `[mailer] EMAIL_USER / EMAIL_APP_PASSWORD not configured — reset code for ${to} is: ${code} ` +
        '(this is only printed to the server console; configure real email credentials before going live)'
    );
    return { delivered: false };
  }

  await mail.sendMail({
    from: process.env.EMAIL_FROM || process.env.EMAIL_USER,
    to,
    subject,
    text,
    html,
  });
  return { delivered: true };
}

module.exports = { sendResetCode, maskEmail };