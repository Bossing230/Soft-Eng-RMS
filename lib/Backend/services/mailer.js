/**
 * Sends the password-reset code by email.
 *
 * WHY THIS CHANGED: Gmail SMTP (ports 465/587) is blocked on free hosting
 * tiers such as Render, so the old nodemailer call hung until it timed out
 * and the email never arrived. Email is now sent over HTTPS, which is never
 * blocked, through the Brevo API (free: 300 emails/day, sends to ANY address
 * after you verify one sender address, no domain needed).
 *
 * Setup (Brevo):
 *   1. Sign up at https://www.brevo.com
 *   2. Senders & IP > Senders > add and verify your sender email.
 *   3. SMTP & API > API Keys > create a key.
 *   4. Set these environment variables on your host (Render > Environment):
 *        BREVO_API_KEY        the key from step 3
 *        BREVO_SENDER_EMAIL   the sender you verified in step 2
 *        EMAIL_FROM_NAME      optional, defaults to "Restaurant Management System"
 *
 * Fallbacks, in order: Brevo API -> SMTP (EMAIL_USER + EMAIL_APP_PASSWORD,
 * only works where SMTP ports are open, e.g. your own PC) -> print the code
 * to the server console (local development only).
 *
 * Every network call has a hard timeout, so a bad connection fails fast
 * instead of leaving the user on an endless spinner.
 */

const SEND_TIMEOUT_MS = 12000;

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
    connectionTimeout: SEND_TIMEOUT_MS,
    greetingTimeout: SEND_TIMEOUT_MS,
    socketTimeout: SEND_TIMEOUT_MS,
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

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

async function sendViaBrevo({ to, name, subject, text, html }) {
  if (!process.env.BREVO_SENDER_EMAIL) throw new Error('BREVO_SENDER_EMAIL is not set');
  const res = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: {
      'api-key': process.env.BREVO_API_KEY,
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify({
      sender: {
        name: process.env.EMAIL_FROM_NAME || 'Restaurant Management System',
        email: process.env.BREVO_SENDER_EMAIL,
      },
      to: [{ email: to, name }],
      subject,
      textContent: text,
      htmlContent: html,
    }),
    signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
  });
  if (!res.ok) {
    throw new Error(`Brevo responded ${res.status}: ${await res.text()}`);
  }
}

async function sendResetCode({ to, name, code }) {
  const subject = 'Your Restaurant Management System password reset code';
  const safeName = escapeHtml(name || 'there');
  const text = `Hi ${name || 'there'},\n\nYour password reset code is: ${code}\n\nThis code expires in 10 minutes. If you didn't request this, you can ignore this email.`;
  const html = `
    <p>Hi ${safeName},</p>
    <p>Your password reset code is:</p>
    <p style="font-size: 28px; font-weight: bold; letter-spacing: 4px;">${code}</p>
    <p>This code expires in 10 minutes. If you didn't request this, you can ignore this email.</p>
  `;

  if (process.env.BREVO_API_KEY) {
    await sendViaBrevo({ to, name, subject, text, html });
    return { delivered: true };
  }

  const mail = getTransporter();
  if (mail) {
    await mail.sendMail({ from: process.env.EMAIL_FROM || process.env.EMAIL_USER, to, subject, text, html });
    return { delivered: true };
  }

  console.warn(
    `[mailer] No email provider configured (set BREVO_API_KEY + BREVO_SENDER_EMAIL). ` +
      `Reset code for ${to} is: ${code} (console only, never reaches the inbox)`
  );
  return { delivered: false };
}

module.exports = { sendResetCode, maskEmail };