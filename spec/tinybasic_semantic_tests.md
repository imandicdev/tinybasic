# Tiny BASIC Semantic Tests (draft)

This file is a checklist for semantic validation tests. Each item is a test case you should implement after the parser produces a typed AST.

## Line numbers
- Reject line number 0
- Reject line number 256
- Reject duplicate line numbers
- Accept out-of-order input; store sorted by line number
- Deleting a line by entering just the number removes it

## Variables
- Accept only single-letter A-Z identifiers for variables
- Reject multi-letter variable names
- Reject non-letter variable names

## IF THEN
- THEN must be followed by a statement
- IF condition requires valid relop
- IF with missing relop should be a syntax error

## GOTO/GOSUB/RETURN
- GOTO target must be integer expression in range 1..255
- GOSUB target must be integer expression in range 1..255
- RETURN in direct mode is a syntax error

## INPUT
- INPUT requires at least one variable
- INPUT with commas requires variable after each comma

## PRINT
- PRINT accepts strings and expressions
- PRINT rejects empty item between commas

## Expressions
- Reject invalid unary operators
- Reject malformed parenthesis
- Reject empty expression
- Reject division by zero (runtime if dynamic)

## CLEAR/RUN/LIST/END
- Must be standalone statement tokens (no suffix letters/digits)

## SAVE/LOAD/BYE
- SAVE requires a quoted file path
- LOAD requires a quoted file path
- BYE should be accepted as a standalone statement
- CLS should be accepted as a standalone statement

## DATA/READ/RESTORE
- DATA requires at least one number
- READ requires at least one variable
- RESTORE should be accepted as standalone

## POKE/PEEK/CALL
- POKE requires address and value expressions
- PEEK can be used inside expressions
- CALL requires a numeric expression
