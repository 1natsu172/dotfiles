#!/usr/bin/env bun

import { readFileSync, existsSync } from "fs";

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

interface TranscriptEntry {
  type: "user" | "assistant" | "summary";
  message?: {
    role: string;
    content: string | any[];
  };
  timestamp?: string;
  uuid?: string;
  toolUseResult?: {
    stdout?: string;
    stderr?: string;
    interrupted?: boolean;
    isImage?: boolean;
  };
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

function readTranscriptFile(transcriptPath: string): TranscriptEntry[] {
  try {
    if (!existsSync(transcriptPath)) {
      return [];
    }

    const content = readFileSync(transcriptPath, "utf-8");
    const lines = content.split("\n").filter((line) => line.trim());

    return lines
      .map((line) => {
        try {
          return JSON.parse(line) as TranscriptEntry;
        } catch {
          return null;
        }
      })
      .filter((entry) => entry !== null) as TranscriptEntry[];
  } catch {
    return [];
  }
}

function isRealUserMessage(entry: TranscriptEntry): boolean {
  return (
    entry.type === "user" &&
    entry.message?.role === "user" &&
    !entry.toolUseResult &&
    entry.timestamp !== undefined
  );
}

function findLatestUserMessage(
  entries: TranscriptEntry[]
): TranscriptEntry | null {
  for (let i = entries.length - 1; i >= 0; i--) {
    const entry = entries[i];
    if (entry && isRealUserMessage(entry)) {
      return entry;
    }
  }
  return null;
}

function getLatestMessageTimestamp(entries: TranscriptEntry[]): string | null {
  for (let i = entries.length - 1; i >= 0; i--) {
    const entry = entries[i];
    if (entry && entry.timestamp) {
      return entry.timestamp;
    }
  }
  return null;
}

function calculateDuration(
  fromTimestamp: string,
  toTimestamp: string
): FormattedTime {
  try {
    const startTime = new Date(fromTimestamp);
    const endTime = new Date(toTimestamp);
    const diffMs = endTime.getTime() - startTime.getTime();

    const totalSeconds = Math.floor(diffMs / 1000);
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;

    return {
      hours: hours > 0 ? hours : undefined,
      minutes: minutes > 0 ? minutes : undefined,
      seconds,
    };
  } catch {
    return { seconds: 0 };
  }
}

function formatDuration(duration: FormattedTime): string {
  const parts: string[] = [];

  if (duration.hours) {
    parts.push(`${duration.hours}h`);
  }
  if (duration.minutes) {
    parts.push(`${duration.minutes}m`);
  }
  parts.push(`${duration.seconds}s`);

  return `💭 ${parts.join(" ")}`;
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

    const entries = readTranscriptFile(statuslineData.transcript_path);
    if (entries.length === 0) {
      console.log(formatDuration({ seconds: 0 }));
      return;
    }

    const latestUserMessage = findLatestUserMessage(entries);
    if (!latestUserMessage || !latestUserMessage.timestamp) {
      console.log(formatDuration({ seconds: 0 }));
      return;
    }

    const latestMessageTimestamp = getLatestMessageTimestamp(entries);
    if (!latestMessageTimestamp) {
      console.log(formatDuration({ seconds: 0 }));
      return;
    }

    const duration = calculateDuration(
      latestUserMessage.timestamp,
      latestMessageTimestamp
    );

    console.log(formatDuration(duration));
  } catch {
    console.log("❌ Error occurred");
  }
}

if (import.meta.main) {
  await main();
}
