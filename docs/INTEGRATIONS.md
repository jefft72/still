# Moving work into and out of Still

Still works with plain text, Markdown, the clipboard, and local app links.
No API key or agent-specific integration is required.

## Import a list

Choose **File > Import Tasks** or press Command-Shift-I.
Paste directly into the text area, or choose a UTF-8 text or Markdown file with **Choose file**.
The task list's options menu also has **Import tasks**.

```markdown
- [ ] Review the diff
- [ ] Check keyboard navigation
- [x] Update the screenshots
```

Each list item becomes a task, and checked items remain completed.
Bullets and numbered lists are accepted; without list markup, each nonempty text line becomes a task.
Markdown headings and fenced code blocks are skipped.
When the text contains list items, surrounding prose is excluded.
Nested lists become a flat task list.

Choose a project and leave **Add to Today** checked to queue the imported work.
Uncheck it to place the tasks in Inbox.
The preview shows the number of tasks and how many are already completed.
Importing appends new tasks and never edits existing ones, so importing the same list twice creates two copies.

An import accepts up to 500 tasks and 200,000 characters.
Files are also limited to 800,000 bytes before decoding.
Links and commands in imported text remain task text; importing does not open or execute them.

## Copy work for another app

**Copy task brief** is available in a task's menu and editor.
It copies a Markdown document containing the title, project if assigned, session length, task notes, and references.
The workspace's separate Notes panel is not included.
References are copied as text, including local file paths when present.

**Copy as checklist** in the task list's options menu copies the current list as Markdown checkboxes.
Completed tasks keep their checked state, including completed tasks hidden by the list's collapsed Completed section.
Paste either format into an editor, issue, or agent conversation.
Still only writes to the clipboard; it does not send the content to another service.

## Create a task with an app link

Install and open Still once so macOS can register its `still://` scheme.
The task endpoint is `still://task`.
New tasks are added to Today, and the workspace opens after the handoff.

| Parameter | Meaning |
| --- | --- |
| `title` | Required, nonempty task title |
| `notes` | Optional task notes, including newlines |
| `project` | Optional project name |
| `minutes` | Optional whole number from 1 to 180; defaults to 25 |
| `url` | Optional HTTP or HTTPS reference with a host and no embedded credentials |

Project names are matched without case sensitivity.
Still reuses a matching project or creates one if needed.
Each successful task link creates a new task; repeating a link does not update an earlier task.

This example uses only the Python standard library to add a review task from a script or agent workflow.
Replace the example reference with the page you want to review.

```python
import subprocess
from urllib.parse import quote, urlencode

parameters = {
    "title": "Review the diff",
    "notes": "Check issue #217 & keyboard behavior.\nConfirm the tests pass.",
    "project": "Website",
    "minutes": "25",
    "url": "https://github.com/example/project/pull/217",
}
url = "still://task?" + urlencode(parameters, quote_via=quote)
subprocess.run(["open", url], check=True)
```

The argument list passes the URL to macOS without invoking a shell.
The link creates local work and opens Still; it does not execute a command, open the reference, start a timer, or play sound.
Local file and folder references can be added in the task editor, but cannot be supplied through the app-link `url` parameter.

## Capture a note

The note endpoint is `still://note` with one required, nonempty `text` parameter.
It adds a note and opens the Notes panel.

```python
import subprocess
from urllib.parse import quote, urlencode

url = "still://note?" + urlencode(
    {"text": "Follow up on issue #217 & the empty state."},
    quote_via=quote,
)
subprocess.run(["open", url], check=True)
```

## Encoding and limits

Encode query values rather than concatenating user text into a URL.
The examples use `quote_via=quote` so spaces become `%20`; Still treats an unescaped `+` as a literal plus sign.
Encode `#` as `%23` and `&` as `%26` inside values so they remain part of the task or note.
Encode a reference URL as a query value too, including any query or fragment it contains.

The complete encoded Still URL must not exceed 200,000 UTF-8 bytes.
Parameter names are case-sensitive, duplicate parameter names are rejected, and unknown parameters are ignored.
Only the `task` and `note` actions are supported, with no extra path, username, password, port, or outer URL fragment.
Invalid links show an error without creating a task or note.
