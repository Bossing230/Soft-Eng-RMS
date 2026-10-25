/**
 * Sends the 6-digit codes (password reset, new-employee email verification).
 *
 * Email goes out over HTTPS through the Brevo API, because SMTP ports are
 * blocked on free hosting tiers such as Render. Environment variables:
 *   BREVO_API_KEY        API key with "Transactional email" set to All
 *   BREVO_SENDER_EMAIL   a sender verified in Brevo
 *   EMAIL_FROM_NAME      optional, defaults to "Restaurant Management System"
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
      to: [name ? { email: to, name } : { email: to }],
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

/** Sends one message through whichever provider is configured. */
async function deliver({ to, name, subject, text, html, code }) {
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
      `Code for ${to} is: ${code} (console only, never reaches the inbox)`
  );
  return { delivered: false };
}

function codeHtml(intro, code, outro) {
  return `
    <p>${intro}</p>
    <p style="font-size: 28px; font-weight: bold; letter-spacing: 4px;">${code}</p>
    <p>${outro}</p>
  `;
}

async function sendResetCode({ to, name, code }) {
  const safeName = escapeHtml(name || 'there');
  const outro = "This code expires in 10 minutes. If you didn't request this, you can ignore this email.";
  return deliver({
    to,
    name,
    code,
    subject: 'Your Restaurant Management System password reset code',
    text: `Hi ${name || 'there'},\n\nYour password reset code is: ${code}\n\n${outro}`,
    html: codeHtml(`Hi ${safeName},<br>Your password reset code is:`, code, outro),
  });
}

/** Code for confirming the email address of an employee account that is being created. */
async function sendVerificationCode({ to, code }) {
  const outro =
    'This code expires in 10 minutes. Give it to the administrator creating your account. ' +
    "If you weren't expecting this, you can ignore this email.";
  return deliver({
    to,
    code,
    subject: 'Verify your email for the Restaurant Management System',
    text: `Your email verification code is: ${code}\n\n${outro}`,
    html: codeHtml('Your email verification code is:', code, outro),
  });
}

module.exports = { sendResetCode, sendVerificationCode, maskEmail };