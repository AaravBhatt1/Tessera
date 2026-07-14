# Tessera - Window Tiling for the Layman!

---

Most window managers for MacOS are made for 'advanced users', requiring them to memorize many keyboard shortcuts, navigate complex config files, and use window tiling all the time. The alternative is to use MacOS' default window snapping features, which are clunky at best. Tessera aims to offer convenient window tiling whilst being more flexible and customizable than the default window snapping.

---

## How to use?

1. Install Tessera from the app store
2. Run Tessera
3. Use `CMD+SHIFT+SPACE` or use the toolbar UI to declutter your windows into a tiled layout
4. [OPTIONAL] Configure tiling preferences using `~/.tessera/rules.conf` and click the 'reload config' button in the toolbar UI

---

## Configuration

By default, Tessera respects the minimum and maximum window sizes of applications.
After applying preferences, it aims to maximize screen utilization and minimize variance in window sizes, without overlapping windows.

Tessera allows users to control how their windows get tiled using rule.
These rules must be written in `~/.tessera/rules.conf` with 1 rule per line.
Line comments can be added by including a hashtag (`#`) at the start of a line.

### Set Clause

Rules at minimum must contain a `set` clause.
This allows users to apply constraint effects to windows.
We use variables to specify windows (they can be called whatever you like but I will mainly use `window` in this tutorial). 
Tessera will attempt to bind variables in a rule to different combinations of windows.

A simple example:
```
set window isBiggerThan (100, 100)
```

This rule will ensure that all windows are bigger than (100, 100). 
If you're unclear how big that is, you can easily view the 'size' of the focused window using the toolbar UI.
But it might be easier to use relative sizing (to the screen) with the percentage sign, `%`.

### When Clause

You can't do very much with only the `set` clause.
That's why we have the `when` clause, which allows us to a bit more picky about which windows are being tiled.

Let's take a look at an example:
```
set window isBiggerThan (700, 400) when window appIs "Mail"
```

The `when` clause can be added either before or after the `set` clause, specifying which windows to apply the constraint effect to. 
In the example, we only apply the effect to Mail windows.

Note that the effect of one rule can sometimes affect the condition of another.
For example, this might occur when the condition depends on the size of a window.
E.g.
```
when window hasContent "netflix" and window isSmallerThan (500, 500) set window isLandscape
```

### Weighting Rules

By default, rules are considered hard constraints meaning they have to hold.
However, too many hard constraints can make tiling impossible and an error message will be shown.
Instead, we can weight rules to make them preferred but not compulsary.

Tessera will try to maximize the maximum total weights added, so higher weights should be given to more important rules.

There are 2 types of weights:
1. Binding weights
2. Rule weights

#### Binding Weights

Binding weights are specified using a colon, like:
```
when window appIs "ghostty" set window isBiggerThan (200, 200) : 5
```
As you can tell, adding a colon and a natural number (`: weight`) at the end of the rule assigns it a binding weight.
This means that every time we bind windows and match it with a condition, we apply the effect with a weight.
Here, Tessera will try to make all my terminals bigger than `(200, 200)`, but it is ok if it cannot do this for one of them.

#### Rule Weights

While binding weights assign a weight per binding of windows, rule weights are more 'all or nothing'.
Consider the example:
```
when window1 appIs "ghostty" and window2 appIs "safari" set window1 isLeftOf window2 | 20
```
Rule weighting uses the pipe (`|`) instead of the colon. 
This rule says that either we put all my terminals to the left of all my Safari windows or we don't (at a higher cost).
We don't want some terminals to be to the left of some of the Safari windows (but not all) here.

### Tagging

Now we can create some more complex rules, but might find ourselves repeating similar effects for similar conditions.
We can use tags to group together windows that might follow the same rules.

For example:
```
# Define what windows are classed as IDEs
when window isApp "XCode" set window hasTag "IDE"
when window isApp "ghostty" and window hasContent "nvim" set window hasTag "IDE"
when window isApp "Safari" and window hasContent "neetcode" set window hasTag "IDE"

# Create general rules for IDEs
when window hasTag "IDE" set window isBiggerThan (60%, 90%) : 10
when window hasTag "IDE" set window isLeftOf otherWindow : 10
```

Clearly, as we scale up to having more rules for IDE-related preferences, using tags is much faster than manually defining the same effects for every window we class as an IDE.

### Dynamic Preferences

Currently, we can't change our tiling preferences without having to go and modify the config file.
This can disrupt your workflow, so instead, we can use dynamic preferences to adjust preferences directly from the toolbar UI.

There are 2 methods of doing this:
1. Locking Positions
2. Dynamic Tagging

#### Locking Positions

Locking positions is quite straightforward.
We can toggle whether a window's position is locked or not by focusing on it (clicking it), and using a button in the toolbar UI.
Locking a window position will fix it in place (as a hard constraint), forcing the other windows to be tiled around it.

#### Dynamic Tagging

Dynamic tagging allows users to create tags can be turned on and off by the user.
The tags themselves must be configured in the `when` clauses of rules.
But once configured, users can use the toolbar UI to toggle which dynamic tags a window has whilst using it.

Dynamic tagging can be used to dynamically adjust sizes, or to handle edge conditions not covered by regular tags.

E.g
```
set window isBiggerThan (40%, 40%) when window hasDynamicTag "big"
```
