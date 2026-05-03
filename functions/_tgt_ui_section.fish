# Render a cyan section divider with a step number and label.
# Used by tgt config and tgt's interactive wizard.
function _tgt_ui_section --argument-names step label
    echo ""
    set_color cyan
    echo "  ─── $step · $label "(string repeat -n (math 50 - (string length $label)) '─')
    set_color normal
end
