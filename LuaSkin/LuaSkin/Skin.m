//
//  Skin.m
//  LuaSkin
//
//  Created by Chris Jones on 11/06/2015.
//  Copyright (c) 2015 Hammerspoon Project Authors. All rights reserved.
//

#import "Skin.h"

@implementation LuaSkin

#pragma mark - Skin Properties

@synthesize L = _L;

#pragma mark - Class lifecycle

+ (id)shared {
    static LuaSkin *sharedLuaSkin = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedLuaSkin = [[self alloc] init];
    });
    if (![NSThread isMainThread]) {
        NSLog(@"GRAVE BUG: LUA EXECUTION ON NON-MAIN THREAD");
        abort();
    }
    return sharedLuaSkin;
}

- (id)init {
    self = [super init];
    if (self) {
        _L = NULL;
        [self createLuaState];
    }
    return self;
}

#pragma mark - lua_State lifecycle

- (void)createLuaState {
    NSLog(@"createLuaState");
    NSAssert((_L == NULL), @"createLuaState called on a live Lua environment", nil);
    _L = luaL_newstate();
    luaL_openlibs(_L);
}

- (void)destroyLuaState {
    NSLog(@"destroyLuaState");
    NSAssert((_L != NULL), @"destroyLuaState called with no Lua environment", nil);
    if (_L) {
        lua_close(_L);
    }
    _L = NULL;
}

- (void)resetLuaState {
    NSLog(@"resetLuaState");
    NSAssert((_L != NULL), @"resetLuaState called with no Lua environment", nil);
    [self destroyLuaState];
    [self createLuaState];
}

#pragma mark - Methods for calling into Lua from C

- (BOOL)protectedCallAndTraceback:(int)nargs nresults:(int)nresults {
    // At this point we are being called with nargs+1 items on the stack, but we need to shove our traceback handler below that

    // Get debug.traceback() onto the top of the stack
    lua_getglobal(_L, "debug");
    lua_getfield(_L, -1, "traceback");
    lua_remove(_L, -2);

    // Move debug.traceback() to the bottom of the stack.
    // The stack currently looks like this, for nargs == 3:
    //  -1 debug.traceback()
    //  -2 argN
    //  -3 argN - 1
    //  -4 argN - 2
    //  -5 function
    //
    // The stack should look like this, for nargs == 3:
    //  -1 argN
    //  -2 argN - 1
    //  -3 argN - 2
    //  -4 function
    //  -5 debug.traceback()
    //
    // Or, for nargs == 0:
    //  -1 function
    //  -2 debug.traceback()
    int tracebackPosition = -nargs - 2;
    lua_insert(_L, tracebackPosition);

    if (lua_pcall(_L, nargs, nresults, tracebackPosition) != LUA_OK) {
        return NO;
    }

    return YES;
}

#pragma mark - Methods for registering libraries with Lua

- (int)registerLibrary:(const luaL_Reg *)functions metaFunctions:(const luaL_Reg *)metaFunctions {
    NSAssert(functions != NULL, @"functions can not be NULL", nil);

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wconstant-conversion"
    luaL_newlib(_L, functions);
    if (metaFunctions != nil) {
        luaL_newlib(_L, metaFunctions);
#pragma GCC diagnostic pop
        lua_setmetatable(_L, -2);
    }
    lua_newtable(_L);
    return luaL_ref(_L, LUA_REGISTRYINDEX);
}

- (int)registerLibraryWithObject:(char *)libraryName functions:(const luaL_Reg *)functions metaFunctions:(const luaL_Reg *)metaFunctions objectFunctions:(const luaL_Reg *)objectFunctions {

    NSAssert(libraryName != NULL, @"libraryName can not be NULL", nil);
    NSAssert(functions != NULL, @"functions can not be NULL (%s)", libraryName);
    NSAssert(objectFunctions != NULL, @"objectFunctions can not be NULL (%s)", libraryName);

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wconstant-conversion"
    luaL_newlib(_L, objectFunctions);
#pragma GCC diagnostic pop
    lua_pushvalue(_L, -1);
    lua_setfield(_L, -2, "__index");
    lua_setfield(_L, LUA_REGISTRYINDEX, libraryName);
    
    int moduleRefTable = [self registerLibrary:functions metaFunctions:metaFunctions];

    return moduleRefTable;
}

- (int)luaRef:(int)refTable {
    NSAssert((refTable != LUA_NOREF && refTable != LUA_REFNIL), @"ERROR: LuaSkin::luaRef was passed a NOREF/REFNIL refTable", nil);

    if (lua_isnil(_L, -1)) {
        return LUA_REFNIL;
    }

    // Push refTable onto the stack
    lua_rawgeti(_L, LUA_REGISTRYINDEX, refTable);

    // Move refTable to second on the stack, underneath the object to reference
    lua_insert(_L, -2);

    // Reference the object at the top of the stack (pops it off)
    int ref = luaL_ref(_L, -2);

    // Remove refTable from the stack
    lua_remove(_L, -1);

    return ref;
}

- (int)luaUnref:(int)refTable ref:(int)ref {
    NSAssert((refTable != LUA_NOREF && refTable != LUA_REFNIL), @"ERROR: LuaSkin::luaUnref was passed a NOREF/REFNIL refTable", nil);

    if (ref != LUA_NOREF && ref != LUA_REFNIL) {
        // Push refTable onto the stack
        lua_rawgeti(_L, LUA_REGISTRYINDEX, refTable);

        // Dereference the supplied ref, from refTable
        luaL_unref(_L, -1, ref);

        // Remove refTable from the stack
        lua_remove(_L, -1);
    }
    return LUA_NOREF;
}

- (int)pushLuaRef:(int)refTable ref:(int)ref {
    NSAssert((refTable != LUA_NOREF && refTable != LUA_REFNIL), @"ERROR: LuaSkin::pushLuaRef was passed a NOREF/REFNIL refTable", nil);
    NSAssert((ref != LUA_NOREF && ref != LUA_REFNIL), @"ERROR: LuaSkin::luaRef was passed a NOREF/REFNIL ref", nil);

    // Push refTable onto the stack
    lua_rawgeti(_L, LUA_REGISTRYINDEX, refTable);

    // Push ref onto the stack
    int type = lua_rawgeti(_L, -1, ref);

    // Remove refTable from the stack
    lua_remove(_L, -2);

    return type;
}

- (void)checkArgs:(int)firstArg, ... {
    int idx = 1;
    int numArgs = lua_gettop(_L);
    int spec = firstArg;

    va_list args;
    va_start(args, firstArg);

    while (true) {
        if (spec == LS_TBREAK) {
            idx--;
            break;
        }

        int lsType;
        int luaType = lua_type(_L, idx);
        char *userdataTag;

        switch (luaType) {
            case LUA_TNONE:
                if (spec & LS_TOPTIONAL) {
                    idx--;
                    goto nextarg;
                }
                lsType = LS_TNONE;
            case LUA_TNIL:
                lsType = LS_TNIL;
                break;
            case LUA_TNUMBER:
                lsType = LS_TNUMBER;
                break;
            case LUA_TSTRING:
                lsType = LS_TSTRING;
                break;
            case LUA_TFUNCTION:
                lsType = LS_TFUNCTION;
                break;
            case LUA_TTABLE:
                lsType = LS_TTABLE;
                break;
            case LUA_TUSERDATA:
                lsType = LS_TUSERDATA;
                userdataTag = va_arg(args, char*);
                if (!luaL_checkudata(_L, idx, userdataTag)) {
                    luaL_error(_L, "ERROR: incorrect userdata type for argument %d", idx);
                }
                break;

            default:
                luaL_error(_L, "ERROR: unknown type '%s' for argument %d", luaL_typename(_L, idx), idx);
                break;
        }

        if (!(spec & lsType)) {
            luaL_error(_L, "ERROR: incorrect type '%s' for argument %d", luaL_typename(_L, idx), idx);
        }
nextarg:
        spec = va_arg(args, int);
        idx++;
    }
    va_end(args);

    if (idx != numArgs) {
        luaL_error(_L, "ERROR: incorrect number of arguments. Expected %d, got %d", idx, numArgs);
    }
}

@end
