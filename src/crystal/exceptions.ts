export class ModelError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ModelError";
  }
}

export class ModelProviderError extends ModelError {
  status_code: number;
  model?: string;

  constructor(message: string, status_code = 502, model?: string) {
    super(message);
    this.name = "ModelProviderError";
    this.status_code = status_code;
    this.model = model;
  }
}

export class ModelRateLimitError extends ModelProviderError {
  constructor(message: string, status_code = 429, model?: string) {
    super(message, status_code, model);
    this.name = "ModelRateLimitError";
  }
}
