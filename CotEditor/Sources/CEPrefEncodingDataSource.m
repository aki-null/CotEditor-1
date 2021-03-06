/*
=================================================
CEPrefEncodingDataSource
(for CotEditor)

 Copyright (C) 2004-2007 nakamuxu.
 Copyright (C) 2014 CotEditor Project
 http://coteditor.github.io
=================================================

encoding="UTF-8"
Created:2004.12.16
 
-------------------------------------------------

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA. 


=================================================
*/

#import "CEPrefEncodingDataSource.h"
#import "constants.h"


@interface CEPrefEncodingDataSource ()

@property (nonatomic) NSMutableArray *encodingsForTmp;
@property (nonatomic, weak) NSIndexSet *draggedIndexes;  // ドラッグ中にのみ必要なオブジェクトなので、retainしない

@property (nonatomic, weak) IBOutlet NSTableView *tableView;
@property (nonatomic, weak) IBOutlet NSButton *delSeparatorButton;
@property (nonatomic, weak) IBOutlet NSButton *revertButton;

@end




#pragma mark -

@implementation CEPrefEncodingDataSource

#pragma mark Public Methods

//=======================================================
// Public method
//
//=======================================================

// ------------------------------------------------------
/// 表示／変更のためのエンコーディングリストをセットアップ
- (void)setupEncodingsToEdit
// ------------------------------------------------------
{
    id values = [[NSUserDefaultsController sharedUserDefaultsController] values];
    NSDictionary *initValues = [[NSUserDefaultsController sharedUserDefaultsController] initialValues];
    NSMutableArray *encodings = [[values valueForKey:k_key_encodingList] mutableCopy];
    BOOL shouldRevert = ![encodings isEqualToArray:initValues[k_key_encodingList]];

    [self setEncodingsForTmp:encodings];
    [[self revertButton] setEnabled:shouldRevert]; // 出荷時に戻すボタンの有効化／無効化を制御
    [[self tableView] reloadData]; // 表示を初期化(これがないとスクロールバーが無効化してしまう)
}


// ------------------------------------------------------
/// エンコーディングリストを userDefaults に書き戻す
- (void)writeEncodingsToUserDefaults
// ------------------------------------------------------
{
    [[NSUserDefaults standardUserDefaults] setObject:[self encodingsForTmp] forKey:k_key_encodingList];
}



#pragma mark Protocol

//=======================================================
// NSTableDataSource Protocol
//
//=======================================================

// ------------------------------------------------------
/// tableView の行数を返す
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
// ------------------------------------------------------
{
    return [[self encodingsForTmp] count];
}


// ------------------------------------------------------
/// tableViewの列・行で指定された内容を返す
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
// ------------------------------------------------------
{
    CFStringEncoding cfEncoding = [[self encodingsForTmp][rowIndex] unsignedLongValue];
    NSString *string;

    if (cfEncoding == kCFStringEncodingInvalidId) { // = separator
        string = @"-----";
    } else {
        NSStringEncoding encoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding);
        NSString *ianaName = (NSString *)CFStringConvertEncodingToIANACharSetName(cfEncoding);
        if (ianaName == nil) {
            ianaName = @"-";
        }
        string = [NSString stringWithFormat:@"%@ : [%@]", [NSString localizedNameOfStringEncoding:encoding], ianaName];
    }
    return string;
}


// ------------------------------------------------------
/// ドラッグ開始／tableView からのドラッグアイテム内容をセット
- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
// ------------------------------------------------------
{
    // ドラッグ受付タイプを登録
    [tableView registerForDraggedTypes:@[k_dropMyselfPboardType]];
    // すべての選択を解除して、改めてドラッグされる行を選択し直す
    [tableView deselectAll:self];
    [tableView selectRowIndexes:rowIndexes byExtendingSelection:YES];
    // ドラッグされる行の保持、Pasteboard の設定
    [self setDraggedIndexes:rowIndexes];
    [pboard declareTypes:@[k_dropMyselfPboardType] owner:nil];
    [pboard setData:[NSData data] forType:k_dropMyselfPboardType];

    return YES;
}


// ------------------------------------------------------
/// tableViewへドラッグアイテムが入ってきたときの判定
- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id <NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)inOperation
// ------------------------------------------------------
{
    if ([info draggingSource]) { // = Local dragging
        BOOL isValid = (((row == k_lastRow) && (inOperation == NSTableViewDropOn)) ||
                        ((row != k_lastRow) && (inOperation == NSTableViewDropAbove)));
        
        return isValid ? NSDragOperationGeneric : NSDragOperationNone;
    }
    return NSDragOperationNone;
}


// ------------------------------------------------------
/// ドロップの許可、アイテムの移動挿入
- (BOOL)tableView:(NSTableView *)tableView 
        acceptDrop:(id <NSDraggingInfo>)info row:(NSInteger)row
        dropOperation:(NSTableViewDropOperation)operation
// ------------------------------------------------------
{
    NSMutableIndexSet *selectIndexSet = [NSMutableIndexSet indexSet];
    NSMutableArray *draggingArray = [NSMutableArray array];
    NSMutableArray *newArray = [[self encodingsForTmp] mutableCopy];
    NSInteger count = [draggingArray count];
    __block NSInteger newRow = row;

    [[self draggedIndexes] enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger idx, BOOL *stop) {
        if (idx < [newArray count]) {
            [draggingArray addObject:[newArray[idx] copy]];
            [newArray removeObjectAtIndex:idx];
            if (idx < row) { // 下方へドラッグ移動されるときの調整
                newRow--;
            }
        }
    }];
    
    for (NSUInteger i = 0; i < count; i++) {
        if (row != k_lastRow) {
            [newArray insertObject:draggingArray[i] atIndex:newRow];
            [selectIndexSet addIndex:(newRow + i)];
        } else {
            [newArray addObject:draggingArray[(count - i - 1)]];
            [selectIndexSet addIndex:i];
        }
    }

    // リストが変更されたら、encodingsForTmp に書き戻す
    if (![newArray isEqualToArray:[self encodingsForTmp]]) {
        [[self encodingsForTmp] setArray:newArray];
    }
    [tableView reloadData];
    [tableView selectRowIndexes:selectIndexSet byExtendingSelection:NO];
    
    return YES;
}



#pragma mark Delegate and Notification

//=======================================================
// Delegate method (NSTableView)
//  <== tableView
//=======================================================

// ------------------------------------------------------
/// tableView の選択行が変更される直前にその許可を出す
- (void)tableViewSelectionDidChange:(NSNotification *)notification
// ------------------------------------------------------
{
    NSIndexSet *selectedIndexes = [[self tableView] selectedRowIndexes];

    if ([selectedIndexes count] > 0) {
        NSUInteger i = 0;
        for (NSNumber *encodingNumber in [self encodingsForTmp]) {
            if ([selectedIndexes containsIndex:i] && ([encodingNumber unsignedLongValue] == kCFStringEncodingInvalidId)) {
                [[self delSeparatorButton] setEnabled:YES];
                return;
            }
            i++;
        }
    }
    [[self delSeparatorButton] setEnabled:NO];
}



#pragma mark Action Messages

//=======================================================
// Action messages
//
//=======================================================

// ------------------------------------------------------
/// デフォルトのエンコーディング設定に戻す
- (IBAction)revertDefaultEncodings:(id)sender
// ------------------------------------------------------
{
    NSDictionary *initValues = [[NSUserDefaultsController sharedUserDefaultsController] initialValues];
    NSMutableArray *encodings = [NSMutableArray arrayWithArray:initValues[k_key_encodingList]];

    [self setEncodingsForTmp:encodings];
    [[self tableView] reloadData];
    [[self revertButton] setEnabled:NO];
}


// ------------------------------------------------------
/// セパレータ追加
- (IBAction)addSeparator:(id)sender
// ------------------------------------------------------
{
    NSUInteger index = MAX([[self tableView] selectedRow], 0);
    
    [[self encodingsForTmp] insertObject:@(kCFStringEncodingInvalidId) atIndex:index];
    [[self tableView] reloadData];
    [[self tableView] selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
}


// ------------------------------------------------------
/// セパレータ削除
- (IBAction)deleteSeparator:(id)sender
// ------------------------------------------------------
{
    NSIndexSet *selectedIndexes = [[self tableView] selectedRowIndexes];

    if ([selectedIndexes count] == 0) {
        return;
    }
    NSMutableArray *encodings = [NSMutableArray array];
    NSUInteger deletedCount = 0;

    NSUInteger i = 0;
    for (NSNumber* encodingNumber in [self encodingsForTmp]) {
        if ([selectedIndexes containsIndex:i] && ([encodingNumber unsignedLongValue] == kCFStringEncodingInvalidId)) {
            deletedCount++;
            continue;
        }
        [encodings addObject:encodingNumber];
        i++;
    }
    if (deletedCount == 0) {
        return;
    }
    [[self tableView] deselectAll:self];
    // リストが変更されたら、encodingsForTmp に書き戻す
    if (![encodings isEqualToArray:[self encodingsForTmp]]) {
        [[self encodingsForTmp] setArray:encodings];
    }
    [[self tableView] reloadData];
}

@end
