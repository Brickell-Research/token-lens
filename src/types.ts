export interface Rate {
  input: number;
  cacheRead: number;
  cacheCreation: number;
  output: number;
}

export interface ContentBlock {
  type: string;
  id?: string;
  name?: string;
  input?: Record<string, unknown>;
  content?: unknown;
  text?: string;
}

export interface Token {
  readonly uuid: string | null;
  readonly parentUuid: string | null;
  readonly requestId: string | null;
  readonly type: string;
  readonly role: string | null;
  readonly model: string | null;
  readonly isSidechain: boolean;
  readonly agentId: string | null;
  readonly content: (string | ContentBlock)[];
  readonly inputTokens: number;
  readonly outputTokens: number;
  readonly cacheReadTokens: number;
  readonly cacheCreationTokens: number;
  readonly marginalInputTokens: number;
  readonly timestamp: string | null;
  readonly isCompaction: boolean;
}

/** Tree node — fields are added in-place by each pipeline stage */
export interface Node {
  token: Token;
  children: Node[];
  depth?: number; // annotator
  subtreeTokens?: number;
  subtreeCost?: number;
  x?: number; // layout
  y?: number;
  w?: number;
  costX?: number;
  costW?: number;
  alt?: boolean; // html renderer
}

export interface RawMessage {
  role?: string;
  model?: string;
  content?: unknown;
  usage?: {
    input_tokens?: number;
    output_tokens?: number;
    cache_read_input_tokens?: number;
    cache_creation_input_tokens?: number;
  };
}

export interface RawEvent {
  uuid?: string;
  parentUuid?: string;
  requestId?: string;
  type?: string;
  timestamp?: string;
  parentToolUseID?: string;
  isSidechain?: boolean;
  message?: RawMessage;
  data?: {
    type?: string;
    agentId?: string;
    message?: {
      uuid?: string;
      requestId?: string;
      type?: string;
      message?: RawMessage;
    };
  };
  event?: RawEvent;
}
