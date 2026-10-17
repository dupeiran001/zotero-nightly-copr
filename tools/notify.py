#!/usr/bin/env python3
"""Send a notification mail for a workflow run over SMTP.

The body comes from --body-file or stdin.  Server details are taken from the
environment so that nothing about the mail account lives in the repository:

  SMTP_HOST   required; without it the script does nothing and exits 0
  SMTP_PORT   default 465 (implicit TLS) or 587 (STARTTLS)
  SMTP_SSL    "1" forces implicit TLS regardless of the port
  SMTP_USER / SMTP_PASS   login; skipped when SMTP_USER is empty
  MAIL_FROM   default "GitHub Actions <actions@github.com>"
  MAIL_TO     required together with SMTP_HOST

Used from .github/workflows/check-upstream.yml as a failure notifier, so a
workflow that has no mail configured still succeeds instead of failing twice.
"""

import argparse
import os
import smtplib
import sys
from email.message import EmailMessage


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--subject", required=True)
    parser.add_argument("--body-file", help="defaults to stdin")
    args = parser.parse_args(argv)

    host = os.environ.get("SMTP_HOST", "").strip()
    recipient = os.environ.get("MAIL_TO", "").strip()
    if not host or not recipient:
        print("::notice::SMTP_HOST or MAIL_TO not set, no mail sent "
              f"(subject: {args.subject})")
        return 0

    try:
        port = int(os.environ.get("SMTP_PORT") or (465 if os.environ.get("SMTP_SSL") == "1" else 587))
    except ValueError:
        print("error: SMTP_PORT is not a number: "
              f"{os.environ.get('SMTP_PORT')!r}", file=sys.stderr)
        return 2

    if args.body_file:
        try:
            with open(args.body_file, encoding="utf-8") as f:
                body = f.read()
        except OSError as exc:
            print(f"error: cannot read the mail body from {args.body_file}: {exc}",
                  file=sys.stderr)
            return 2
    else:
        body = sys.stdin.read()

    sender = os.environ.get("MAIL_FROM") or "GitHub Actions <actions@github.com>"
    user = os.environ.get("SMTP_USER", "").strip()
    password = os.environ.get("SMTP_PASS", "")

    mail = EmailMessage()
    mail["Subject"] = args.subject
    mail["From"] = sender
    mail["To"] = recipient
    mail.set_content(body)

    implicit_tls = os.environ.get("SMTP_SSL") == "1" or port == 465
    try:
        if implicit_tls:
            server = smtplib.SMTP_SSL(host, port, timeout=60)
        else:
            server = smtplib.SMTP(host, port, timeout=60)
    except OSError as exc:
        print(f"error: cannot connect to {host}:{port}: {exc}", file=sys.stderr)
        return 1

    try:
        with server:
            server.ehlo()
            secure = implicit_tls
            if server.has_extn("starttls") and not implicit_tls:
                server.starttls()
                server.ehlo()
                secure = True
            if user and not secure and os.environ.get("SMTP_INSECURE") != "1":
                print(f"error: {host}:{port} offers no TLS, refusing to send credentials over it. "
                      "Use SMTP_SSL=1 or port 465 (SMTP_INSECURE=1 only for a local "
                      "test).", file=sys.stderr)
                return 1
            if user:
                server.login(user, password)
            server.send_message(mail)
    except (smtplib.SMTPException, OSError) as exc:
        print(f"error: could not send mail to {recipient} via {host}:{port}: {exc}",
              file=sys.stderr)
        return 1

    print(f"mail sent to {recipient}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
