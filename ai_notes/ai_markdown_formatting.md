# Markdown Document Formatting Requirements for AI Agents

## Purpose

These requirements ensure consistent, clean markdown output that meets specific linting and formatting standards. AI agents must follow these rules when generating markdown documentation.

## Core Formatting Rules

### Content Restrictions

- No code snippets or implementation code in markdown files
- No fenced code blocks without a language identifier
- No bold text using double asterisks (avoid **text**)
- Rely on document outline structure to convey information hierarchy
- Detail what is to be used and how it is to be used, not actual implementations

### Heading and Section Spacing

- No blank lines immediately after headings
- Single blank line between subsections (### and #### level headings)
- Double blank lines between major sections (## level headings)
- Headings followed immediately by content or next-level heading

### Paragraph Formatting

- No blank lines between consecutive paragraphs within the same section
- Paragraphs flow continuously within their section
- Hard line breaks at specific character counts for readability
- Text wrapping maintains natural reading flow

### List Formatting

- Use dash (-) for all unordered list items at all levels
- No blank lines between list items at any level
- 2-space indentation for nested list levels
- Lists flow continuously without vertical spacing gaps
- Lists must be surrounded by blank lines (MD032 rule)
- Blank line required before first list item
- Blank line required after last list item

### Fenced Code Blocks

- Every fenced code block must have a language identifier
- Format: ```language not```
- Valid identifiers: bash, python, json, yaml, etc.
- Never use unmarked fences (plain ```)

## Emphasis and Formatting

### Text Emphasis

- Avoid bold text using **text** syntax
- Use heading hierarchy to emphasize importance
- Use list structure to organize related items
- Let document outline provide visual structure

### Structural Emphasis

- Rely on heading levels (##, ###, ####) for hierarchy
- Use list nesting to show relationships
- Use consistent indentation to show grouping
- Allow whitespace patterns to guide reading

## Document Structure

### Organization

- Clear hierarchical heading structure
- Consistent section ordering
- Logical information flow
- Related content grouped together

### Readability

- Hard line breaks for paragraph flow
- Consistent spacing patterns
- Clean visual separation between sections
- Minimal vertical whitespace within sections

## Spacing Summary

### Between Elements

- Major sections (##): Two blank lines
- Subsections (###, ####): One blank line
- Paragraphs in same section: No blank lines
- List items: No blank lines
- After headings: No blank lines
- Before lists: One blank line (MD032)
- After lists: One blank line (MD032)

### Indentation

- Nested lists: 2 spaces per level
- Continuation lines: Align with parent content
- Consistent throughout document

## Examples of Correct Formatting

### Section with Multiple Paragraphs

Major section starts here.
First paragraph of content flows naturally without break.
Second paragraph follows immediately without blank line between them.
Third paragraph continues the pattern.

### Section with Lists

Major section with list content:

- First item flows from heading
- Second item with no gap
- Third item continues
  - Nested item with 2-space indent
  - Another nested item
- Back to top level

Note the blank line before and after the list block.

### Section Transitions

Previous section ends here.

Next major section begins after double blank line.
Content continues flowing naturally.

## Quality Checklist

When generating markdown, verify:

- No bold text using asterisks
- All fenced blocks have language identifiers
- No blank lines after headings
- No blank lines between paragraphs in same section
- No blank lines between list items
- Single blank line between subsections
- Double blank line between major sections
- 2-space indentation for nested lists
- Blank line before each list (MD032)
- Blank line after each list (MD032)
- Document relies on structure, not formatting tricks
- Content explains what and how, not implementations
