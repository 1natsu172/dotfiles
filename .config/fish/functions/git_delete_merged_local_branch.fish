function git_delete_merged_local_branch -d 'マージ済みのブランチを一括削除する'
  if test (count $argv) -eq 0
    set ignore_branch "^\*|master\$"
  else
    set ignore_branch "^\*|master\$|$argv"
  end

  git branch --merged | grep -vE $ignore_branch | xargs -I % git branch -d %
end