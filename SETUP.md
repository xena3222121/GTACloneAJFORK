# GTA-Clone-Godot — Team Setup

## 1. Install Godot

We're on **Godot 4.7.2**. Download the standard (non-.NET) Windows build:
https://godotengine.org/download/windows/

No installer — just unzip it and run the `.exe`.

## 2. Install Git

If you don't already have it: https://git-scm.com/download/win
Use the default options during install.

## 3. Get repo access

You'll get an email invite from GitHub (sent to your @heavydutypartscompany.com
address) to collaborate on `Timbo9688/GTA-Clone-Godot` — it's a **private** repo.
Accept that invite first (you may need a free GitHub account if you don't have
one already).

## 4. Clone the project

Open a terminal (PowerShell or Git Bash) wherever you keep projects, and run:

```
git clone https://github.com/Timbo9688/GTA-Clone-Godot.git
```

The first time you push, Git will pop up a "Connect to GitHub" sign-in window —
sign in with your GitHub account there.

## 5. Open it in Godot

Launch Godot, click **Import**, and point it at the `project.godot` file inside
the folder you just cloned. Let it finish importing assets (first time only,
takes a minute or two) before hitting Play.

## 6. Day-to-day workflow

Basic loop, every time you sit down to work:

```
git pull                     # get everyone else's latest changes first
```

...do your work in Godot...

```
git add -A
git commit -m "short description of what you changed"
git push
```

A few things worth knowing:

- **Pull before you start working**, every session — avoids conflicts.
- **Commit in small, described chunks** rather than one giant commit at the
  end of the day. Makes it much easier to undo just the one thing that broke,
  instead of everything.
- If `git push` fails because someone else pushed first, run `git pull` again
  to merge their changes in, then push.
- **Scene files (`.tscn`) don't merge well** if two people edit the *same*
  scene at the same time — git will flag a conflict and you'll have to
  manually pick which version to keep. Where possible, split up who's working
  on which scene to avoid this.

## 7. Restoring if something breaks

Nothing is ever really lost once it's pushed. To see the save history:

```
git log --oneline
```

To pull an old version of everything back (without erasing the broken
version's history):

```
git checkout <commit-hash> -- .
```

If you're not sure what to run, just ask Tim — he can also have me
(Claude) do it directly against the repo.
