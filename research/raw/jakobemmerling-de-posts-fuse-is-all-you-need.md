---
title: "FUSE is All You Need - Giving agents access to anything via filesystems"
url: "https://jakobemmerling.de/posts/fuse-is-all-you-need/"
date_fetched: "2026-02-16"
type: webpage
---

Title: FUSE is All You Need - Giving agents access to anything via filesystems

URL Source: https://jakobemmerling.de/posts/fuse-is-all-you-need/

Published Time: 2026-01-11T00:00:00Z

Markdown Content:
Giving agents access to a sandboxed environment with a shell and a filesystem has been the latest hype when it comes to agentic harnesses. Recent examples of this include:

*   [Turso’s AgentFS](https://github.com/tursodatabase/agentfs)
*   Anthropic’s [Agent SDK](https://platform.claude.com/docs/en/agent-sdk/overview), which brings Claude Code’s harness to non-coding domains
*   Vercel [rebuilding their text-to-SQL agent](https://vercel.com/blog/we-removed-80-percent-of-our-agents-tools) on top of a sandbox
*   Anthropic’s [Agent Skills](https://github.com/anthropics/skills) for filesystem-based progressive disclosure

The argument for why this is good goes something like this:

> The big labs are doing heavy RL for coding tasks in these kinds of environments. Aligning more closely with such a harness brings free gains from the coding domain to other problem spaces.

Beyond that, replacing a bunch of search/write/move/list tools with a single Bash tool reduces the tool space significantly. Agents can chain operations together intuitively. Unix paradigms give you good tool design for free.

On top of that there is more nice patterns that emerge from having a filesystem, for example:

*   **Plan/scratch files**: Agents can create temporary files to organize their thoughts, track progress, or store intermediate results. This emerges naturally from having filesystem access, no need to design a separate “notepad” tool.
*   **Long context handling**: As conversations grow, you can compact old messages and tool results into files on the filesystem. The agent can re-read them when needed rather than keeping everything in context.

So the advantages are clear. But how do you actually apply this to your domain? This is where things get tricky. Consider two examples:

1.   **A domain with parallels to filesystems**: For example an agent for organizing emails. There are folders, items (emails), and you can browse them and move things around.

2.   **An existing platform that already looks like a filesystem**: For example an agent inside Google Drive.

When you try to fit these into a sandboxed filesystem you might wonder:

*   When do I copy over the files?
*   Do I copy over everything?
*   How do I write back updates that the agent made?
*   When do I sync edits made by a human?
*   How do I show folders/files progressively as the agent progresses? (Particularly useful if you want to lean into the filesystem as a tool to manage long context.)

[A reply](https://x.com/SeeLos/status/2009806164935000211?s=20) to a recent post on X from Vercel about building filesystem-based agents puts it well:

> This article doesn’t really answer that question though.
> 
> 
> They explain the shape of the filesystem really well, but the missing piece is still the main question for existing apps: how do you actually materialize Postgres + object storage + APIs into that sandbox FS in a practical and scalable way? “Preload files” is hand-wavy without a recommended ingestion/snapshot pattern.

This post will show a pattern to close that gap: turning anything into a filesystem with the help of FUSE.

An example: Email agent
-----------------------

To make this tangible, let’s build a fictional agent.

Imagine we’re building an AI-powered email platform, think Gmail but with AI on top. We have our own database storing emails, folders, and contacts. We have a UI that users interact with.

Now we want to add a powerful agent on top of that platform. We could build a simple agent loop with tools like `list-emails`, `move-email`, `read-email`, but as we established there’s a more ergonomic approach: put our emails in a filesystem.

After some thinking, we come up with the following file layout for the agent’s sandbox:

```
workspace/
  Inbox/
    Customer Inquiry - Size Chart (emily.wolfe@gmail.com)
    PO Confirmation #2026-0038 (supplierC@fabricdirect.com)
    Shipping Delay Notice (supplierA@logisticsco.com)
    Partnership Proposal - TrendCircle (marketing@trendcircle.io)

  Starred/
    Wholesale Inquiry - SilverLeaf Boutique (boutique@silverleaf.co)
    Re: Restock ETA For Red Jackets (supplierA@logisticsco.com)

  Needs_Action/
    Missing Documents - Customs (carrier-support@airbridge.co)
    Last Call: VAT Filing Deadline (gov-tax@tradeportal.gov)

  Orders/
    2026/
      Feb/
        PO Confirmation #2026-0038 (supplierC@fabricdirect.com)
        Shipping Delay Notice (supplierA@logisticsco.com)

  Customers/
    Returns/
      Return Request #8743 (john.hartley@yahoo.com)

  Sent/
    Re: Customer Inquiry - Size Chart (emily.wolfe@gmail.com)
```

Now comes the problem: we need to bridge the gap from our database to the sandboxed filesystem that the agent uses to consume our data.

How to turn anything into a FS, enter FUSE
------------------------------------------

[FUSE](https://www.kernel.org/doc/html/v6.3/filesystems/fuse.html) stands for _Filesystem in Userspace_. It’s a framework that lets you implement filesystems outside the kernel, while the kernel makes it look like a ‘real’ filesystem to the rest of Linux. You just write a userland process that implements the actual filesystem logic.

A FUSE filesystem needs to implement a small, well-defined interface: `lookup`, `open`, `read`, `write`, `readdir`, `create`, `unlink`, etc. Whenever the OS interacts with the mounted filesystem, operations get forwarded to your userspace implementation. This indirection makes it possible to expose arbitrary data structures as if they were files.

There are wrappers and bindings for higher-level languages that let you write these filesystems in the language and tech stack of your choice. No need to dive into C :)

Architecture
------------

Coming back to our email agent, here’s how FUSE would fit into a very high-level architecture:

![Image 1: Architecture of the email agent](https://jakobemmerling.de/posts/fuse-is-all-you-need/fuse.svg) The top row shows the traditional path: users interact with your app through a UI that talks to a backend, which reads and writes to a database.

The bottom row shows the agent path: the agent runs inside a sandbox and sees a mounted filesystem. When it does `ls /workspace/Inbox`, that call hits the FUSE layer, which translates it into a query against the same backend. The agent and your users are looking at the same data through different interfaces.

You can think of the filesystem as a UI layer for the agent. Just like your frontend decides how to present data to users, your FUSE implementation decides how to present data to the agent. Realistically you’ll have additional tools for actions that don’t map well to filesystem operations (like sending an email), but for browsing, reading, and organizing data, the filesystem abstraction works great.

For this blog post we’ll keep things simple: the agent loop and FUSE implementation both run inside a Docker container, talking directly to a database. We are going to implement this in Typescript using the [fuse-native](https://github.com/fuse-friends/fuse-native) library. In production you’d want to structure things a bit differently, like running the agent loop outside the sandbox and have your FUSE bindings be only a thin client that calls out to your backend with proper authentication for example.

Implementing the filesystem operations
--------------------------------------

To make our data accessible via the filesystem, we need to implement the subset of FUSE operations relevant for our use case. Let’s start with listing directories (`readdir`):

```
export async function readdir(path: string, cb: (err: number, names?: string[]) => void) {
  const [folder] = await db.select().from(foldersTable).where(eq(foldersTable.path, path));

  if (!folder) {
    return cb(Fuse.ENOENT);
  }

  const emailsInFolder = await db.select({
    email: emailsTable,
    sender: contactsTable,
  }).from(emailsTable)
  .leftJoin(contactsTable, eq(emailsTable.sender, contactsTable.id))
  .where(eq(emailsTable.folderId, folder.id));

  const entries = new Set<string>();

  for (const {email, sender} of emailsInFolder) {
    entries.add(`${email.subject} (${sender.email}).eml`);
  }

  const subfolders = await db.select().from(foldersTable).where(like(foldersTable.path, sql`${path}/%`));
  for (const subfolder of subfolders) {
    entries.add(subfolder.path.split("/").pop() || "");
  }

  cb(0, Array.from(entries));
}
```

We match which email folder we’re in based on the filesystem path, list all emails inside that folder, and add any subfolders. Together with implementing `getattr` (to get file attributes), this makes listing and navigating the folder tree via `ls` work.

To choose how email content will be represented we implement `read` like this:

```
export async function read(path: string, fd: number, buf: Buffer, len: number, pos: number, cb: (err: number) => void) {
  const email = await getEmailById(fd);
  if (!email) {
    return cb(Fuse.ENOENT);
  }
  const content = emailToContent(email);
  const slice = content.slice(pos, pos + len);
  const bytesRead = buf.write(slice);
  cb(bytesRead);
}

export function emailToContent(email: EmailWithSender): string {
  return `From: ${email.senderEmail}
Date: ${email.sentAt.toISOString()}
Subject: ${email.subject}
X-Folder: ${email.folderPath}
X-Starred: ${email.starred}
X-Needs-Action: ${email.needsAction}

${email.body}
`;
}
```

There are a few more operations I implemented like `open`, `mkdir`, and `rename` to allow moving email files around and reassigning folder IDs in the database.

On top of that, I introduced the concept of _virtual folders_—the `Starred` and `Needs_Action` folders in the layout above. They work like this: if an email has the starred or needsAction flag set, it appears in these folders. Because an email can be both starred and part of an actual folder, the Starred folder contains symlinks to the “actual” files. The agent can unlink these files or create new links to flip attributes on the email. This might be overkill and better covered via regular tools, but I wanted to see how far I could lean into the filesystem abstraction. For this to work, I implemented additional FUSE operations: `readlink`, `symlink`, `unlink`, and adjusted the existing ones.

Deciding how to map your domain to a filesystem is really a context engineering challenge in the end. The key is finding the right balance between leveraging familiar filesystem semantics and not over-abstracting to the point where the mapping becomes confusing.

With all the filesystem operations defined, we’re ready to mount it and see it in action. While it’s possible to get this working on a Mac via [macFUSE](https://macfuse.github.io/), I chose the easier path and spun up a Docker container and mounted the filesystem there.

Here’s a quick demo of navigating the filesystem. As you can see, it looks and works just like regular files.`grep`, `mv`, `ls` all behave as expected. The best part? There’s no risk of anything going out of sync because we read directly from the database. We also only load the things we needed when they are accessed instead of preloading our entire database into a sandbox.

Giving the agent access to it
-----------------------------

Now that we have the filesystem working, it’s time to hook up an agent and see how it performs. I used the Anthropic Agent SDK to whip up a quick filesystem agent with tools to run Bash, Read, Glob, etc. To give the agent some context about the filesystem, I added the following system prompt:

```
You are an email assistant helping the user manage their inbox.

You have access to a filesystem at /workspace representing their email:

- Folders: Inbox, Sent, Orders, Customers, etc.
- Emails: .eml files named "Subject (sender@email.com).eml"
- Filenames contain spaces (from email subjects), so always quote paths in shell commands
- Starred/Needs_Action: contain symlinks to flagged emails

Commands you use internally:
- ls, cat, find → browse emails
- mv → move emails between folders
- ln -s <email> /Starred/ → star an email
- rm /Starred/<email> → unstar an email
- mkdir → create folders

When responding to the user:
- Describe emails by subject and sender, not filenames
- Say "starred" not "created symlink"
- Say "moved to Orders" not "mv to /Orders/"
- Summarize what you found/did in plain language
```

Let’s see how it approaches some common user queries:

```
> which emails do i have in my Inbox?

I'll check your Inbox to see what emails you have.

[Bash] ls -la /workspace/Inbox/

You have 6 emails in your Inbox:

1. **"Missing Documents - Customs"** from carrier-support@airbridge.co (Jan 4)
2. **"PO Confirmation #2026-0038"** from supplierC@fabricdirect.com (Jan 9)
3. **"Partnership Proposal - TrendCircle"** from marketing@trendcircle.io (Jan 7)
4. **"Re: Restock ETA For Red Jackets"** from supplierA@logisticsco.com (Jan 5)
5. **"Shipping Delay Notice"** from supplierA@logisticsco.com (Jan 8)
6. **"Wholesale Inquiry - SilverLeaf Boutique"** from boutique@silverleaf.co (Jan 6)

Would you like me to read any of these emails or help you organize them?
```

```
> find the email about that wholesale inquiry, i need to remember to follow up on it

I'll help you find the wholesale inquiry email. Let me search for it.

[Bash] find /workspace -type f -name "*.eml" -exec grep -l "wholesale" {} \;

Found it! There's a wholesale inquiry from SilverLeaf Boutique (boutique@silverleaf.co) in your Inbox.

Would you like me to:
1. Star it so you can easily find it later to follow up?
2. Move it to a specific folder?
3. Show you the email content?

> show me the email and star it

[Read] /workspace/Inbox/Wholesale Inquiry - SilverLeaf Boutique (boutique@silverleaf.co).eml

[Bash] ln -s "/workspace/Inbox/Wholesale Inquiry - SilverLeaf Boutique (boutique@silverleaf.co).eml" /workspace/Starred/

Here's the email:

**From:** boutique@silverleaf.co
**Date:** January 6, 2026
**Subject:** Wholesale Inquiry - SilverLeaf Boutique

**Message:**
"We're a boutique in Portland and interested in carrying your line. What are your wholesale terms?"

Good news - this email is already starred! It looks like it was already flagged for follow-up. SilverLeaf Boutique is interested in carrying your products and wants to know about your wholesale terms.
```

```
> Organize my Inbox

I'll help you organize your inbox. Let me first see what emails you have there.

[Bash] ls -la /workspace/Inbox/

Now let me check what folders you already have set up:

[Bash] ls -d /workspace/*/

Perfect! I can see you have 8 emails in your inbox. Let me organize them into appropriate folders:

[Bash] mv "/workspace/Inbox/Customer Inquiry - Size Chart (emily.wolfe@gmail.com).eml" /workspace/Customers/
[Bash] mv "/workspace/Inbox/Wholesale Inquiry - SilverLeaf Boutique (boutique@silverleaf.co).eml" /workspace/Customers/
[Bash] mv "/workspace/Inbox/PO Confirmation #2026-0038 (supplierC@fabricdirect.com).eml" /workspace/Orders/
[Bash] mv "/workspace/Inbox/Re: Restock ETA For Red Jackets (supplierA@logisticsco.com).eml" /workspace/Orders/
[Bash] mv "/workspace/Inbox/Shipping Delay Notice (supplierA@logisticsco.com).eml" /workspace/Orders/
Now let me flag the urgent items that need action:
[Bash] ln -s "/workspace/Inbox/Last Call: VAT Filing Deadline (gov-tax@tradeportal.gov).eml" /workspace/Needs_Action/
[Bash] ln -s "/workspace/Inbox/Missing Documents - Customs (carrier-support@airbridge.co).eml" /workspace/Needs_Action/

Good - those urgent items are already flagged. Now let me check if the partnership proposal might be something to consider:

[Bash] cat "/workspace/Inbox/Partnership Proposal - TrendCircle (marketing@trendcircle.io).eml"

Let me create a folder for business opportunities and move the partnership proposal there:

[Bash] mkdir -p /workspace/Business_Opportunities && mv "/workspace/Inbox/Partnership Proposal - TrendCircle (marketing@trendcircle.io).eml" /workspace/Business_Opportunities/

Let me verify your inbox is now organized:

[Bash] ls /workspace/Inbox/

Perfect! I've organized your inbox. Here's what I did:

**Moved to Customers folder (2 emails):**
- Customer Inquiry - Size Chart from emily.wolfe@gmail.com
- Wholesale Inquiry - SilverLeaf Boutique from boutique@silverleaf.co

**Moved to Orders folder (3 emails):**
- PO Confirmation #2026-0038 from supplierC@fabricdirect.com
- Re: Restock ETA For Red Jackets from supplierA@logisticsco.com
- Shipping Delay Notice from supplierA@logisticsco.com

**Moved to new Business_Opportunities folder (1 email):**
- Partnership Proposal - TrendCircle from marketing@trendcircle.io

**Left in Inbox (2 urgent items - already flagged):**
- Last Call: VAT Filing Deadline from gov-tax@tradeportal.gov ⚠️
- Missing Documents - Customs from carrier-support@airbridge.co ⚠️

The two remaining emails in your inbox are urgent items that need your immediate attention - they're already flagged in your Needs_Action folder.
```

It’s pretty cool to see how the agent just navigates through the filesystem given the task and a minimal system prompt. We didn’t spend any time on tool design. We just mapped our domain to a filesystem and got intuitive tool behavior for free.

Outlook
-------

You can find the full implementation on GitHub: [https://github.com/Jakob-em/agent-fuse](https://github.com/Jakob-em/agent-fuse) to play around with yourself. I also might write a follow up to this post about evaling this approach vs a traditional agent loop to see if this way of building agents brings any measurable gains.

In general there is a lot more potential for virtual filesystems for context engineering. You could include old conversations as files on the filesystem, or make old tool call results appear as files after compacting context. The possibilities are endless, and as long as coding agents remain relevant, this way of designing context will only get more ergonomic for models.

My prediction is that one of the many sandbox providers will come up with a nice API on top of this that lets you do something like:

```
new Agent({
    tool: [...]
	sandbox: {
        filesystem: {
            '/emails': (folder) => listEmails(folder),
            '/old_conversations': () => listOldConversations(),
        }
	 }
    }
})
```

No worrying about FUSE, the sandbox, where things are executed, etc. This will be a huge differentiator and make virtual filesystems easily accessible to everyone.
