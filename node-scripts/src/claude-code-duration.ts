#!/usr/bin/env bun

import { readFileSync, existsSync, statSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

interface StatuslineInput {
  session_id: string;
  transcript_path: string;
  cwd: string;
  model: {
    id: string;
    display_name: string;
  };
  workspace: {
    current_dir: string;
    project_dir: string;
  };
  version: string;
  cost: {
    total_cost_usd: number;
    total_duration_ms: number;
    total_api_duration_ms: number;
    total_lines_added: number;
    total_lines_removed: number;
  };
}

interface DurationData {
  sessionId: string;
  startTimestamp: string;
  lastUpdate: string;
  duration: number;
  status: "active" | "finished" | "interrupted";
}

interface FormattedTime {
  hours?: number;
  minutes?: number;
  seconds: number;
}

function parseStatuslineInput(input: string): StatuslineInput | null {
  try {
    return JSON.parse(input);
  } catch {
    return null;
  }
}

function readDurationData(sessionId: string): DurationData | null {
  try {
    const tmpFile = join(tmpdir(), `claude-code-duration-${sessionId}.json`);

    if (!existsSync(tmpFile)) {
      return null;
    }

    const content = readFileSync(tmpFile, "utf-8");
    const data = JSON.parse(content) as DurationData;

    // TODO: 実際のhookの情報からinturruptかどうかを判断する。現在の実装は期待値通りではない
    // ファイル更新から5分以上経過している場合は中断とみなす
    const fileStats = statSync(tmpFile);
    const now = Date.now();
    const fileModified = fileStats.mtime.getTime();
    const timeSinceUpdate = now - fileModified;

    if (data.status === "active" && timeSinceUpdate > 5 * 60 * 1000) {
      data.status = "interrupted";
    }

    return data;
  } catch {
    return null;
  }
}

function formatDuration(durationMs: number): FormattedTime {
  const totalSeconds = Math.floor(durationMs / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  return {
    hours: hours > 0 ? hours : undefined,
    minutes: minutes > 0 ? minutes : undefined,
    seconds,
  };
}

function formatDurationString(duration: FormattedTime, status: string): string {
  const parts: string[] = [];

  if (duration.hours) {
    parts.push(`${duration.hours}h`);
  }
  if (duration.minutes) {
    parts.push(`${duration.minutes}m`);
  }
  parts.push(`${duration.seconds}s`);

  const statusIcon =
    status === "finished" ? "✅" : status === "interrupted" ? "🗣️" : "💭";
  return `${statusIcon} ${parts.join(" ")}`;
}

async function main() {
  try {
    let input = "";
    for await (const chunk of process.stdin) {
      input += chunk.toString();
    }

    const statuslineData = parseStatuslineInput(input);
    if (!statuslineData) {
      console.log("❌ Parse error");
      return;
    }

    const durationData = readDurationData(statuslineData.session_id);
    if (!durationData) {
      console.log(formatDurationString({ seconds: 0 }, "active"));
      return;
    }

    const formattedDuration = formatDuration(durationData.duration);
    console.log(formatDurationString(formattedDuration, durationData.status));
  } catch {
    console.log("❌ Error occurred");
  }
}

if (import.meta.main) {
  await main();
}
