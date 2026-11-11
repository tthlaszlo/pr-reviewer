export type Group = 'awaiting' | 'waiting' | 'requested-again';
export type PullRequest = {
  id: number;
  number: number;
  title: string;
  url: string;
  repository: string;
  author: string;
  updatedAt: string;
  draft: boolean;
  group: Group;
  personal: boolean;
  teams: string[];
  reviewState: string | null;
  changedSinceReview: boolean;
  uncertain: boolean;
};
export type Inbox = {
  pulls: PullRequest[];
  warnings: string[];
  syncedAt: string;
};
export type Session = {
  configured: boolean;
  user: { login: string } | null;
  installUrl: string | null;
};
