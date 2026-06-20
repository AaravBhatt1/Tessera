# Notes

- Use a domain specific language to define 'rules;
    - This should be like prolog, e.g.
        - when hasTitle(window, "VSCode"), tag(window, IDE), tag(window, big), minimumWidth(window, 300)
        - when tag(window, IDE) and (tag(window, big) or isFocused(window)), preferredAspectRatio(portrait)
    - Note: Convert AST such that every rule has one condition with a bunch of ands, and one effect
    - Evaluate rules with tagging effects first, and then evaluate rules with constraint effects
- Predictive tagging? Use app name and description to infer tag based on how users manually tag things
        
