function gco --description "alias git branch create or switch if exist"
  git switch $argv[1] 2>/dev/null || git switch -c $argv[1];
end
