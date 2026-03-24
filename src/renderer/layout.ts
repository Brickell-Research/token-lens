import { costUsd, displayWidth, flattenNodes } from "../token";
import type { Node } from "../types";

export function annotate(nodes: Node[], depth = 0): void {
  for (const node of nodes) {
    node.depth = depth;
    annotate(node.children, depth + 1);
    const childTokens = node.children.reduce((sum, c) => sum + (c.subtreeTokens ?? 0), 0);
    const childCost = node.children.reduce((sum, c) => sum + (c.subtreeCost ?? 0), 0);
    node.subtreeTokens = Math.max(displayWidth(node.token), 1) + childTokens;
    node.subtreeCost = costUsd(node.token) + childCost;
  }
}

const CANVAS_WIDTH = 1200;
const ROW_HEIGHT = 32;
const MIN_THREAD_WIDTH = 80;

export function layout(nodes: Node[]): number {
  const maxDepth = flattenNodes(nodes).reduce((max, n) => Math.max(max, n.depth ?? 0), 0);
  const effectiveWidth = Math.max(CANVAS_WIDTH, nodes.length * MIN_THREAD_WIDTH);

  const total = nodes.reduce((sum, n) => sum + (n.subtreeTokens ?? 0), 0);
  const scale = total > 0 ? effectiveWidth / total : 1.0;
  position(nodes, 0, scale, maxDepth);

  const totalCost = nodes.reduce((sum, n) => sum + (n.subtreeCost ?? 0), 0);
  const costScale = totalCost > 0 ? effectiveWidth / totalCost : 1.0;
  positionCost(nodes, 0, costScale, maxDepth);

  return effectiveWidth;
}

function position(nodes: Node[], x: number, scale: number, maxDepth: number): void {
  let cursor = x;
  for (const node of nodes) {
    const start = Math.round(cursor);
    cursor += (node.subtreeTokens ?? 0) * scale;
    node.x = start;
    node.y = (maxDepth - (node.depth ?? 0)) * ROW_HEIGHT;
    node.w = Math.round(cursor) - start;
    position(node.children, node.x, scale, maxDepth);
  }
}

function positionCost(nodes: Node[], x: number, scale: number, maxDepth: number): void {
  let cursor = x;
  for (const node of nodes) {
    const start = Math.round(cursor);
    cursor += (node.subtreeCost ?? 0) * scale;
    node.costX = start;
    node.costW = Math.round(cursor) - start;
    positionCost(node.children, node.costX, scale, maxDepth);
  }
}
