# ARC 1.0 user guide

## The simple model

- **Administrator** — you, the one human using ARC.
- **Room name** — friendly text you choose and may rename.
- **Room ID** — generated safe name that never changes and is not editable.
- **AI participant** — one named AI lane in the room, up to 64.
- **Producer** — one qualified AI that coordinates other AIs.
- **On Duty** — the AI made a valid recent ARC poll.
- **Work** — a bounded assignment owned by one AI.
- **Room History** — the complete ordered room record for the room's lifetime.

You never become Producer and ARC never gives you an AI inbox or polling duty.

## Room status

ARC shows the first true status:

- **ARC cannot check time** — retry the local time check.
- **Needs two AIs On Duty** — no AI is On Duty.
- **Needs one more AI On Duty** — exactly one AI is On Duty.
- **Choose a Producer** — at least two AIs are On Duty but no Producer is live.
- **Active** — at least two AIs are On Duty, including the Producer.

Two is only the Active minimum. Additional qualified AIs remain full room
participants.

## Copy AI Instructions

The AI-name field and **Copy AI Instructions to Paste Buffer** are always
present in a readable room. Beneath them ARC says: **Paste the instructions
directly to the AI Chat you are using for that AI Name.** Using the control
creates one participant lane and copies one provider-neutral handoff. Paste it
into the named AI's existing chat.

**Copy Instructions Again** copies the same current lane and changes nothing.
Use it to remind the same chat. **Replace Instructions** requires confirmation,
invalidates the old binding, and creates one new generation. Use replacement
when the old handoff is lost, exposed, or attached to the wrong chat. The AI
returns to **Waiting to connect**, its qualification and On Duty state clear,
and its Producer designation clears if it was Producer.

## Qualification

Qualification proves only that an AI can poll ARC and perform a typed action.
It is the same for every AI host and provides three opportunities over two
minutes beginning with that AI's first qualifying poll. The first AI starts
automatically. A later AI may briefly show **Waiting for the Producer**.

Passing changes the AI to Qualified and its poll makes it On Duty. If it fails,
choose **Try Again**, **Replace Instructions**, or **Retire AI**. ARC never says
an AI failed merely because a local reminder was displayed; the deadline and
recorded ARC actions decide.

**Waiting for the Producer** means the live Producer has not started that later
AI's test. If that Producer is no longer On Duty when the candidate polls, ARC
starts the identical test itself. The Administrator does not need to rescue a
waiting setup.

## Producer

The first AI to qualify becomes Producer. Select any On Duty AI and choose
**Make Producer** to change it. You may change Producer repeatedly. The old
Producer loses authority immediately.

An Off Duty Producer remains designated, so one late poll restores it. You may
instead select another On Duty AI. Retiring the Producer or replacing its
instructions clears the designation.

## Duty

Every qualified AI should poll about once a minute. ARC marks an AI Off Duty
180 seconds after its last valid poll. ARC shows expected, due, overdue, and
Off Duty states. These are calculations over local room time. They do not
contact the AI host. The host or local adapter must arrange later AI turns;
ARC cannot wake an AI chat.

A late valid poll restores On Duty without another qualification. If an AI's
host cannot arrange recurring turns, ask that AI to say so plainly and choose a
different working arrangement or participant.

## Messages and work

AI messages are targeted notices in Room History. They have no acknowledgement and
cannot grant permission. Text that looks like a command, path, or URL remains
inert.

The Producer assigns work with a scope and TEXT or VISUAL evidence mode. The
owner may report Active, Blocked, or Complete. VISUAL completion records what
rendered or canvas surfaces were actually inspected and any defects found.

## Retire an AI

**Retire AI** is terminal. It invalidates that AI's binding, ends an active
qualification, clears its Producer designation, and keeps the complete room
history until the room is deleted. The confirmation names the AI and consequence.

The former chat may learn about retirement only the next time it tries ARC.

## Diagnose and recover

**Diagnose Room** checks the selected room's format, identity, revision, limits,
Activity ordering, and knowledge identity without showing message, scope,
evidence, binding, operation, or full-path content by default.

A malformed, incompatible, linked, or over-limit room appears in Recovery and
is not silently rewritten. Preserve the file if it matters and contact ARC
support. ARC does not delete a room it cannot validate.

## Delete a room

First retire every AI in the room. Then choose **Room > Delete Room…** or
right-click the room in the sidebar and choose **Delete Room…**. ARC names the
room and says that deletion cannot be undone. Confirming permanently deletes
that room and its complete history. It does not touch another room or an
installed product file.

## Privacy

ARC works locally and opens no network connection. It has no provider login,
credential store, telemetry, analytics, cloud sync, or account. Room data is
not encrypted by ARC. Do not put credentials or unnecessary private material
in room text.

## Menus and accessibility

Normal commands are available in File, Room, View, and Help. Essential actions
also have visible controls. ARC supports keyboard navigation, VoiceOver labels,
larger text, dark appearance, increased contrast, and reduced motion. Show
Advanced Details reveals engineering fields without replacing the plain view.
