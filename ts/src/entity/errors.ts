export class TaskComplete extends Error {
  message: string;
  constructor(message: string) {
    super(message);
    this.name = "TaskComplete";
    this.message = message;
  }
}
