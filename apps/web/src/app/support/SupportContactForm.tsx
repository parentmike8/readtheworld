"use client";

import { useMemo, useState } from "react";

type FormState = "idle" | "sending" | "sent" | "error";

function supportEndpoint() {
  if (process.env.NEXT_PUBLIC_SUPPORT_CONTACT_URL) {
    return process.env.NEXT_PUBLIC_SUPPORT_CONTACT_URL;
  }
  const projectId = process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID || "read-the-world-74f2a";
  return `https://us-central1-${projectId}.cloudfunctions.net/submitSupportContact`;
}

export function SupportContactForm() {
  const endpoint = useMemo(() => supportEndpoint(), []);
  const [state, setState] = useState<FormState>("idle");
  const [error, setError] = useState("");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [message, setMessage] = useState("");
  const [company, setCompany] = useState("");

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");

    const trimmedName = name.trim();
    const trimmedEmail = email.trim().toLowerCase();
    const trimmedMessage = message.trim();
    if (!trimmedName) {
      setError("Add your name.");
      setState("error");
      return;
    }
    if (!trimmedEmail.includes("@")) {
      setError("Add a valid email.");
      setState("error");
      return;
    }
    if (trimmedMessage.length < 4) {
      setError("Add a little more detail.");
      setState("error");
      return;
    }

    setState("sending");
    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: trimmedName,
          email: trimmedEmail,
          message: trimmedMessage,
          company,
        }),
      });
      const data = await response.json().catch(() => ({})) as { message?: string };
      if (!response.ok) {
        throw new Error(data.message || "Message could not be sent.");
      }
      setState("sent");
      setName("");
      setEmail("");
      setMessage("");
      setCompany("");
    } catch (sendError) {
      setError(sendError instanceof Error ? sendError.message : "Message could not be sent.");
      setState("error");
    }
  }

  return (
    <form className="supportForm" onSubmit={submit}>
      <label>
        <span>Name</span>
        <input
          value={name}
          onChange={(event) => setName(event.target.value)}
          autoComplete="name"
          maxLength={120}
          required
        />
      </label>
      <label>
        <span>Email</span>
        <input
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          type="email"
          autoComplete="email"
          maxLength={254}
          required
        />
      </label>
      <label className="supportHiddenField" aria-hidden="true">
        <span>Company</span>
        <input
          value={company}
          onChange={(event) => setCompany(event.target.value)}
          tabIndex={-1}
          autoComplete="off"
        />
      </label>
      <label>
        <span>Message</span>
        <textarea
          value={message}
          onChange={(event) => setMessage(event.target.value)}
          maxLength={4000}
          rows={7}
          required
        />
      </label>
      <button type="submit" disabled={state === "sending"}>
        {state === "sending" ? "Sending..." : "Send message"}
      </button>
      {state === "sent" ? (
        <p className="supportStatus">Sent. We&apos;ll get back to you by email.</p>
      ) : null}
      {state === "error" && error ? <p className="supportStatus error">{error}</p> : null}
    </form>
  );
}
