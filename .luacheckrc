std = "luajit"
cache = true
codes = true
max_line_length = 120

globals = { "vim" }

files["tests/"] = {
  read_globals = {
    "after_each",
    "assert",
    "before_each",
    "describe",
    "it",
    "pending",
  },
}
