const std = @import("std");

pub const Program = struct {
    lines: []Line,
};

pub const Line = struct {
    number: ?i32,
    stmt: ?*Stmt,
    line: u32,
    column: u32,
};

pub const Stmt = struct {
    tag: StmtTag,
    data: StmtData,
};

pub const StmtTag = enum {
    let_stmt,
    goto_stmt,
    gosub_stmt,
    return_stmt,
    if_then,
    input_stmt,
    print_stmt,
    end_stmt,
    list_stmt,
    run_stmt,
    clear_stmt,
    cls_stmt,
    data_stmt,
    read_stmt,
    restore_stmt,
    poke_stmt,
    call_stmt,
    save_stmt,
    load_stmt,
    chain_stmt,
    bye_stmt,
};

pub const StmtData = union(StmtTag) {
    let_stmt: LetStmt,
    goto_stmt: ExprRef,
    gosub_stmt: ExprRef,
    return_stmt: void,
    if_then: IfThenStmt,
    input_stmt: InputStmt,
    print_stmt: PrintStmt,
    end_stmt: void,
    list_stmt: void,
    run_stmt: void,
    clear_stmt: void,
    cls_stmt: void,
    data_stmt: DataStmt,
    read_stmt: ReadStmt,
    restore_stmt: void,
    poke_stmt: PokeStmt,
    call_stmt: CallStmt,
    save_stmt: FileStmt,
    load_stmt: FileStmt,
    chain_stmt: FileStmt,
    bye_stmt: void,
};

pub const LetStmt = struct {
    var_index: u8,
    value: ExprRef,
};

pub const IfThenStmt = struct {
    left: ExprRef,
    op: RelOp,
    right: ExprRef,
    then_stmt: *Stmt,
};

pub const InputStmt = struct {
    vars: []u8,
};

pub const PrintStmt = struct {
    items: []PrintItem,
};

pub const DataStmt = struct {
    values: []i32,
};

pub const ReadStmt = struct {
    vars: []u8,
};

pub const PokeStmt = struct {
    addr: ExprRef,
    value: ExprRef,
};

pub const CallStmt = struct {
    target: ExprRef,
};

pub const FileStmt = struct {
    path: []const u8,
};

pub const PrintItem = union(enum) {
    string: []const u8,
    expr: ExprRef,
};

pub const RelOp = enum {
    equal,
    less,
    less_equal,
    greater,
    greater_equal,
    not_equal,
};

pub const Expr = struct {
    tag: ExprTag,
    data: ExprData,
};

pub const ExprTag = enum {
    number,
    variable,
    unary,
    binary,
    peek,
};

pub const ExprData = union(ExprTag) {
    number: i32,
    variable: u8,
    unary: UnaryExpr,
    binary: BinaryExpr,
    peek: ExprRef,
};

pub const UnaryExpr = struct {
    op: UnaryOp,
    expr: ExprRef,
};

pub const BinaryExpr = struct {
    op: BinaryOp,
    left: ExprRef,
    right: ExprRef,
};

pub const UnaryOp = enum {
    plus,
    minus,
};

pub const BinaryOp = enum {
    add,
    sub,
    mul,
    div,
};

pub const ExprRef = *Expr;
