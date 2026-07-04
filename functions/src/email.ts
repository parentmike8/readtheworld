import { defineSecret } from "firebase-functions/params";

export const postmarkServerToken = defineSecret("POSTMARK_SERVER_TOKEN");

export const POSTMARK_FROM = "Read the World <hello@readtheworld.today>";
export const POSTMARK_TRANSACTIONAL_STREAM = "outbound";
export const POSTMARK_DAILY_STREAM = process.env.POSTMARK_DAILY_STREAM || "outbound";

export type PostmarkEmail = {
  to: string;
  subject: string;
  htmlBody: string;
  textBody: string;
  messageStream: string;
  tag?: string;
  metadata?: Record<string, string>;
};

type PostmarkResponse = {
  MessageID?: string;
  ErrorCode?: number;
  Message?: string;
};

export function isValidEmail(value: unknown): value is string {
  return typeof value === "string" &&
    value.length <= 254 &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) &&
    !value.includes("..");
}

export async function sendPostmarkEmail(email: PostmarkEmail): Promise<PostmarkResponse> {
  const token = postmarkServerToken.value();
  if (!token) {
    throw new Error("POSTMARK_SERVER_TOKEN is not configured.");
  }

  const response = await fetch("https://api.postmarkapp.com/email", {
    method: "POST",
    headers: {
      "Accept": "application/json",
      "Content-Type": "application/json",
      "X-Postmark-Server-Token": token,
    },
    body: JSON.stringify({
      From: POSTMARK_FROM,
      To: email.to,
      Subject: email.subject,
      HtmlBody: email.htmlBody,
      TextBody: email.textBody,
      MessageStream: email.messageStream,
      Tag: email.tag,
      Metadata: email.metadata,
    }),
  });
  const body = await response.json().catch(() => ({})) as PostmarkResponse;
  if (!response.ok || (body.ErrorCode ?? 0) !== 0) {
    throw new Error(`Postmark send failed: ${response.status} ${body.Message ?? ""}`.trim());
  }
  return body;
}

export function verificationEmail(input: {
  to: string;
  displayName: string;
  verificationUrl: string;
}): PostmarkEmail {
  const name = firstName(input.displayName);
  const subject = "Confirm your read";
  return {
    to: input.to,
    subject,
    messageStream: POSTMARK_TRANSACTIONAL_STREAM,
    tag: "email-verification",
    htmlBody: emailFrame({
      preheader: "Confirm your email for Read the World.",
      eyebrow: "READ THE WORLD",
      title: `Welcome${name ? `, ${escapeHtml(name)}` : ""}.`,
      body: [
        "Before the room settles in, confirm this is your email.",
        "After that, your rooms, scores, and daily reminders stay tied to the right account.",
      ],
      ctaLabel: "Confirm email",
      ctaUrl: input.verificationUrl,
    }),
    textBody: [
      `Welcome${name ? `, ${name}` : ""}.`,
      "",
      "Confirm this email for Read the World:",
      input.verificationUrl,
    ].join("\n"),
  };
}

export function dailyHabitEmail(input: {
  to: string;
  displayName: string;
  roomsUrl: string;
  dailyKey: string;
}): PostmarkEmail {
  const name = firstName(input.displayName);
  return {
    to: input.to,
    subject: "Your rooms are ready",
    messageStream: POSTMARK_DAILY_STREAM,
    tag: "daily-habit",
    metadata: { dailyKey: input.dailyKey },
    htmlBody: emailFrame({
      preheader: "New questions are open, and yesterday's rooms are ready to reveal.",
      eyebrow: "TODAY'S READ",
      title: name ? `${escapeHtml(name)}, your rooms are ready.` : "Your rooms are ready.",
      body: [
        "New questions are open for today.",
        "If your rooms played yesterday, the reveal is waiting too: the split, the surprises, and who read the room best.",
      ],
      ctaLabel: "Open today's rooms",
      ctaUrl: input.roomsUrl,
    }),
    textBody: [
      name ? `${name}, your rooms are ready.` : "Your rooms are ready.",
      "",
      "New questions are open for today. If your rooms played yesterday, the reveal is waiting too.",
      input.roomsUrl,
    ].join("\n"),
  };
}

export function memberJoinedEmail(input: {
  to: string;
  displayName: string;
  joinedName: string;
  roomName: string;
  roomUrl: string;
}): PostmarkEmail {
  return {
    to: input.to,
    subject: `${input.joinedName} joined ${input.roomName}`,
    messageStream: POSTMARK_TRANSACTIONAL_STREAM,
    tag: "room-member-joined",
    htmlBody: emailFrame({
      preheader: `${input.joinedName} joined ${input.roomName}.`,
      eyebrow: "ROOM UPDATE",
      title: `${escapeHtml(input.joinedName)} joined ${escapeHtml(input.roomName)}.`,
      body: [
        "Your room has one more read in the mix.",
        "Open the room to see today's questions and who still needs to play.",
      ],
      ctaLabel: "Open room",
      ctaUrl: input.roomUrl,
    }),
    textBody: [
      `${input.joinedName} joined ${input.roomName}.`,
      "",
      "Open the room:",
      input.roomUrl,
    ].join("\n"),
  };
}

function emailFrame(input: {
  preheader: string;
  eyebrow: string;
  title: string;
  body: string[];
  ctaLabel: string;
  ctaUrl: string;
}): string {
  const bodyHtml = input.body
    .map((paragraph) => `<p style="margin:0 0 16px;color:#3f3d38;font:16px/1.55 Georgia,serif;">${escapeHtml(paragraph)}</p>`)
    .join("");
  return `<!doctype html>
<html>
  <head>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta http-equiv="Content-Type" content="text/html charset=UTF-8">
  </head>
  <body style="margin:0;background:#f5f1e9;">
    <div style="display:none;max-height:0;overflow:hidden;opacity:0;">${escapeHtml(input.preheader)}</div>
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5f1e9;padding:32px 16px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#fffaf2;border:1px solid #ded7c9;border-radius:18px;overflow:hidden;">
            <tr>
              <td style="padding:32px 32px 26px;">
                <div style="color:#a96b42;font:700 12px/1.2 Arial,sans-serif;letter-spacing:2.8px;margin-bottom:18px;">${escapeHtml(input.eyebrow)}</div>
                <h1 style="margin:0 0 18px;color:#1f1d19;font:400 34px/1.06 Georgia,serif;letter-spacing:0;">${input.title}</h1>
                ${bodyHtml}
                <div style="padding-top:10px;">
                  <a href="${escapeHtml(input.ctaUrl)}" style="display:inline-block;background:#1f1d19;color:#fffaf2;text-decoration:none;border-radius:999px;padding:14px 22px;font:700 15px/1 Arial,sans-serif;">${escapeHtml(input.ctaLabel)}</a>
                </div>
              </td>
            </tr>
            <tr>
              <td style="border-top:1px solid #e6dfd2;padding:18px 32px;color:#8a8579;font:13px/1.5 Arial,sans-serif;">
                Read the World sends this because it relates to your account or reminder settings.
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;
}

function firstName(value: string): string {
  const trimmed = value.trim();
  if (!trimmed || trimmed.toLowerCase() === "reader") return "";
  return trimmed.split(/\s+/)[0] ?? "";
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
