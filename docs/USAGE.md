# Using Still

Still keeps a task list and a focus timer together in a native Mac workspace.
All data stays on your Mac; no account or network connection is required.

## Tasks and projects

Type a task in the entry row and press Return.
Tasks added in Today are queued for work; tasks added in Inbox stay there until you choose **Add to Today** from their menu.
Create projects from the sidebar to group related tasks.
Removing a project keeps its tasks and removes their project assignment.

Click a task title to edit its notes, session length, project, and references.
References can be web links, local files, or folders.
Still stores references to files, not copies, so moving a file may break its reference.
The task menu can move work to the top or bottom, change its queue membership, or remove it.
Use the Undo button to restore the most recently removed task.

## Import and hand off work

Choose **File > Import Tasks** or press Command-Shift-I to paste a multiline list or Markdown checklist.
The task list's options menu offers the same import action.
Use **Choose file** to read a UTF-8 text or Markdown file instead.
Choose a project and whether to add the imported tasks to Today, then review the task count before importing.
Checked checklist items remain completed, and existing tasks stay unchanged.
Each import accepts up to 500 tasks and 200,000 characters.

Choose **Copy task brief** from a task's menu or editor to copy its title, project, session length, task notes, and references as Markdown.
Choose **Copy as checklist** from the task list's options menu to copy the current list, including completion states.
These actions use the clipboard so you can paste work into another app or an agent conversation.

Still also accepts local `still://task` and `still://note` links from scripts and other apps.
A link adds the task or note and opens the workspace without starting a timer, playing sound, or opening its references.
See [Integrations](INTEGRATIONS.md) for URL parameters and a Python handoff example.

## Focus sessions

Click the play button beside a task to start a session with its title and configured duration.
You can also type a session title directly without selecting a task.
Change the duration before starting; presets and custom durations from 1 to 180 minutes are available.

Pause freezes the remaining time until you resume.
An unpaused timer continues while Still is closed or your Mac sleeps.
Ending an unfinished session does not add it to History.
A completed session is recorded once, even if you reopen Still after its deadline.
Completing a session does not complete its task; use the task checkbox when the work is done.

## Notes and sound

Open Notes to capture thoughts without switching away from your work.
Press Return to save a note or Shift-Return for a new line.
Resolve a note with its checkmark, and use **Show resolved notes** to recover it later.
Long notes can expand without dominating the panel.

Background sound offers Rain, Shore, and Ember, generated on the Mac without audio downloads.
Sound starts only when you choose it.
Your sound and volume preferences are remembered, but playback is off after relaunch.
Completing or ending a session stops the sound.

## Mini player and menu bar

The mini player floats above other windows and can move between desktops.
It shares the workspace timer and offers the same pause and resume controls.
Closing the workspace leaves Still in the menu bar.
The menu bar shows remaining time during a session and a completion indicator afterward.
Use **Quit Still** to exit the app.

## Search and history

Command-K finds tasks by title, notes, or project name, and can open a project directly.
Use the arrow keys to navigate results and Return to open one.
History shows actual completed sessions and the last seven local calendar days of focus time.
Filter by period or search title and project, then export the visible sessions as CSV.
CSV text is escaped and protected against spreadsheet formula execution.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Add a task | Command-N |
| Capture a note | Command-Shift-N |
| Import tasks | Command-Shift-I |
| Search tasks and projects | Command-K |
| Start, pause, or resume | Command-Return |
| Open the mini player | Command-Shift-M |
| Open the workspace | Command-1 |
| Save task edits | Command-Return |

## Local data

Task, project, note, and session data lives at `~/Library/Application Support/Still/state.json`.
Audio preferences are stored in the app's macOS preferences domain.
The state file is versioned and saved atomically.
If the file cannot be read, Still reports the error and preserves the original instead of overwriting it.
Quit Still before manually copying or restoring this file.
