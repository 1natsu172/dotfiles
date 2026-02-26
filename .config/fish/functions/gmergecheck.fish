function gmergecheck --description "Check if a branch can be merged without conflicts (via merge-tree)"
  if test (count $argv) -eq 0
    echo "Usage: gmergecheck <base> [<source>]"
    echo "  Check if <source> can be merged into <base> without conflicts."
    echo "  <source> defaults to the current branch."
    return 1
  end

  set -l base $argv[1]
  set -l source (test (count $argv) -ge 2; and echo $argv[2]; or git branch --show-current)

  for ref in $base $source
    if not git rev-parse --verify $ref &>/dev/null
      echo "Error: '$ref' not found"
      return 1
    end
  end

  echo "Checking if '$source' can be merged into '$base'..."

  # merge-tree: in-memory merge — no working tree/index changes, no cleanup needed
  # exit 0 = clean merge, exit 1 = conflicts, other = error
  set -l output (git merge-tree --write-tree --name-only --messages $base $source 2>&1)
  set -l exit_code $status

  switch $exit_code
    case 0
      echo "✓ No conflicts. Merge is possible."
      return 0
    case 1
      echo "✗ Conflicts detected:"
      # Skip first line (tree OID), print conflicted file names and messages
      for line in $output[2..]
        test -n "$line"; and echo "  $line"
      end
      return 1
    case '*'
      echo "Error: merge-tree failed"
      echo $output
      return 2
  end
end
