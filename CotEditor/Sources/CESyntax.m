/*
=================================================
CESyntax
(for CotEditor)

 Copyright (C) 2004-2007 nakamuxu.
 Copyright (C) 2014 CotEditor Project
 http://coteditor.github.io
=================================================

encoding="UTF-8"
Created:2004.12.22
 
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

#import "CESyntax.h"
#import "CELayoutManager.h"
#import "CEEditorView.h"
#import "CESyntaxManager.h"
#import "CEIndicatorSheetController.h"
#import "RegexKitLite.h"
#import "DEBUG_macro.h"
#import "constants.h"


@interface CESyntax ()

@property (nonatomic, copy) NSDictionary *coloringDictionary;
@property (nonatomic, copy) NSDictionary *simpleWordsCharacterSets;

@property (nonatomic, copy) NSString *wholeString;
@property (nonatomic, copy) NSString *localString;  // カラーリング対象文字列
@property (nonatomic) NSRange updateRange;
@property (nonatomic) NSColor *textColor;
@property (nonatomic) NSColor *singleQuotesColor;
@property (nonatomic) NSColor *doubleQuotesColor;
@property (nonatomic) CEIndicatorSheetController *indicatorController;


// readonly
@property (nonatomic, copy, readwrite) NSArray *completionWords;
@property (nonatomic, copy, readwrite) NSCharacterSet *firstCompletionCharacterSet;

@end




#pragma mark -

@implementation CESyntax

static NSArray *kSyntaxDictKeys;


#pragma mark Superclass Class Methods

// ------------------------------------------------------
/// クラスの初期化
+ (void)initialize
// ------------------------------------------------------
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray *syntaxDictKeys = [[NSMutableArray alloc] initWithCapacity:k_size_of_allColoringArrays];
        for (NSUInteger i = 0; i < k_size_of_allColoringArrays; i++) {
            [syntaxDictKeys addObject:k_SCKey_allColoringArrays[i]];
        }
        kSyntaxDictKeys = [syntaxDictKeys copy];
    });
}



#pragma mark Public Methods

//=======================================================
// Public method
//
//=======================================================

// ------------------------------------------------------
/// 保持するstyle名をセット
- (void)setSyntaxStyleName:(NSString *)styleName
// ------------------------------------------------------
{
    CESyntaxManager *manager = [CESyntaxManager sharedManager];
    NSArray *names = [manager styleNames];

    if ([names containsObject:styleName] || [styleName isEqualToString:NSLocalizedString(@"None", nil)]) {
        [self setColoringDictionary:[manager styleWithStyleName:styleName]];

        [self setCompletionWordsFromColoringDictionary];
        [self setSimpleWordsCharacterSet];

        _syntaxStyleName = styleName;
    }
}


// ------------------------------------------------------
/// 拡張子からstyle名をセット
- (BOOL)setSyntaxStyleNameFromExtension:(NSString *)extension
// ------------------------------------------------------
{
    NSString *name = [[CESyntaxManager sharedManager] syntaxNameFromExtension:extension];

    if (name && ![[self syntaxStyleName] isEqualToString:name]) {
        [self setSyntaxStyleName:name];
        return YES;
    }
    return NO;
}


// ------------------------------------------------------
/// 全体をカラーリング
- (void)colorAllString:(NSString *)wholeString
// ------------------------------------------------------
{
    if (([wholeString length] == 0) || ([[self syntaxStyleName] length] == 0)) { return; }

    [self setWholeString:wholeString];
    [self setUpdateRange:NSMakeRange(0, [[self wholeString] length])];

    if ([self coloringDictionary] == nil) {
        [self setColoringDictionary:[[CESyntaxManager sharedManager] styleWithStyleName:[self syntaxStyleName]]];
        [self setCompletionWordsFromColoringDictionary];
        [self setSimpleWordsCharacterSet];
    }
    if ([self coloringDictionary] == nil) { return; }

    [self doColoring];
    [self setWholeString:nil];
}


// ------------------------------------------------------
/// 表示されている部分をカラーリング
- (void)colorVisibleRange:(NSRange)range wholeString:(NSString *)wholeString
// ------------------------------------------------------
{
    if (([wholeString length] == 0) || ([[self syntaxStyleName] length] == 0)) { return; }
    
    [self setWholeString:wholeString];

    NSRange effectiveRange;
    NSUInteger start = range.location;
    NSUInteger end = NSMaxRange(range) - 1;
    NSUInteger wholeLength = [[self wholeString] length];

    // 直前／直後が同色ならカラーリング範囲を拡大する
    [[self layoutManager] temporaryAttributesAtCharacterIndex:start
                                        longestEffectiveRange:&effectiveRange
                                                      inRange:NSMakeRange(0, wholeLength)];

    start = effectiveRange.location;
    [[self layoutManager] temporaryAttributesAtCharacterIndex:end
                                        longestEffectiveRange:&effectiveRange
                                                      inRange:NSMakeRange(0, wholeLength)];

    end = (NSMaxRange(effectiveRange) < wholeLength) ? NSMaxRange(effectiveRange) : wholeLength;

    [self setUpdateRange:NSMakeRange(start, end - start)];
    if ([self coloringDictionary] == nil) {
        [self setColoringDictionary:[[CESyntaxManager sharedManager] styleWithStyleName:[self syntaxStyleName]]];
        [self setCompletionWordsFromColoringDictionary];
        [self setSimpleWordsCharacterSet];
    }
    if ([self coloringDictionary] == nil) { return; }

    [self doColoring];
    [self setWholeString:nil];
}


// ------------------------------------------------------
/// アウトラインメニュー用の配列を生成し、返す
- (NSArray *)outlineMenuArrayWithWholeString:(NSString *)wholeString
// ------------------------------------------------------
{
    __block NSMutableArray *outlineMenuDicts = [NSMutableArray array];
    
    if (([wholeString length] == 0) || ([[self syntaxStyleName] length] == 0)) {
        return outlineMenuDicts;
    }
    
    NSUInteger menuTitleMaxLength = [[NSUserDefaults standardUserDefaults] integerForKey:k_key_outlineMenuMaxLength];
    NSArray *definitions = [self coloringDictionary][k_SCKey_outlineMenuArray];
    
    for (NSDictionary *definition in definitions) {
        NSRegularExpressionOptions options = NSRegularExpressionAnchorsMatchLines;
        if ([definition[k_SCKey_ignoreCase] boolValue]) {
            options |= NSRegularExpressionCaseInsensitive;
        }

        NSError *error = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:definition[k_SCKey_beginString]
                                                                               options:options
                                                                                 error:&error];
        if (error) {
            NSLog(@"ERROR in \"%s\" with regex pattern \"%@\"", __PRETTY_FUNCTION__, definition[k_SCKey_beginString]);
            continue;  // do nothing
        }
        
        NSString *template = definition[k_SCKey_arrayKeyString];
        // 置換テンプレート内の $& を $0 に置換
        template = [template stringByReplacingOccurrencesOfString:@"(?<!\\\\)\\$&"
                                                       withString:@"\\$0"
                                                          options:NSRegularExpressionSearch
                                                            range:NSMakeRange(0, [template length])];
        
        [regex enumerateMatchesInString:wholeString
                                options:0
                                  range:NSMakeRange(0, [wholeString length])
                             usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop)
         {
             // セパレータのとき
             if ([template isEqualToString:CESeparatorString]) {
                 [outlineMenuDicts addObject:@{k_outlineMenuItemRange: [NSValue valueWithRange:[result range]],
                                               k_outlineMenuItemTitle: CESeparatorString,
                                               k_outlineMenuItemSortKey: @([result range].location)}];
                 return;
             }
             
             // メニュー項目タイトル
             NSString *title;
             
             if ([template length] == 0) {
                 // パターン定義なし
                 title = [wholeString substringWithRange:[result range]];;
                 
             } else {
                 // マッチ文字列をテンプレートで置換
                 title = [regex replacementStringForResult:result
                                                  inString:wholeString
                                                    offset:0
                                                  template:template];
                 
                 // マッチした範囲の開始位置の行を得る
                 NSUInteger lineNum = 0, index = 0;
                 while (index <= [result range].location) {
                     index = NSMaxRange([wholeString lineRangeForRange:NSMakeRange(index, 0)]);
                     lineNum++;
                 }
                 //行番号（$LN）置換
                 title = [title stringByReplacingOccurrencesOfString:@"(?<!\\\\)\\$LN"
                                                          withString:[NSString stringWithFormat:@"%tu", lineNum]
                                                             options:NSRegularExpressionSearch
                                                               range:NSMakeRange(0, [title length])];
             }
             
             // 改行またはタブをスペースに置換
             title = [title stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
             title = [title stringByReplacingOccurrencesOfString:@"\t" withString:@"    "];
             
             // 長過ぎる場合は末尾を省略
             if ([title length] > menuTitleMaxLength) {
                 title = [NSString stringWithFormat:@"%@ ...", [title substringToIndex:menuTitleMaxLength]];
             }
             
             // ボールド
             BOOL isBold = [definition[k_SCKey_bold] boolValue];
             // イタリック
             BOOL isItalic = [definition[k_SCKey_italic] boolValue];
             // アンダーライン
             NSUInteger underlineMask = [definition[k_SCKey_underline] boolValue] ?
                                        (NSUnderlineByWordMask | NSUnderlinePatternSolid | NSUnderlineStyleThick) : 0;
             
             // 辞書生成
             [outlineMenuDicts addObject:@{k_outlineMenuItemRange: [NSValue valueWithRange:[result range]],
                                           k_outlineMenuItemTitle: title,
                                           k_outlineMenuItemSortKey: @([result range].location),
                                           k_outlineMenuItemFontBold: @(isBold),
                                           k_outlineMenuItemFontItalic: @(isItalic),
                                           k_outlineMenuItemUnderlineMask: @(underlineMask)}];
        }];
    }
    
    if ([outlineMenuDicts count] > 0) {
        // 出現順にソート
        NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:k_outlineMenuItemSortKey
                                                                   ascending:YES
                                                                    selector:@selector(compare:)];
        [outlineMenuDicts sortUsingDescriptors:@[descriptor]];
        
        // 冒頭のアイテムを追加
        [outlineMenuDicts insertObject:@{k_outlineMenuItemRange: [NSValue valueWithRange:NSMakeRange(0, 0)],
                                         k_outlineMenuItemTitle: NSLocalizedString(@"<Outline Menu>", nil),
                                         k_outlineMenuItemSortKey: @0U}
                               atIndex:0];
    }
    
    return outlineMenuDicts;
}



#pragma mark Private Mthods

//=======================================================
// Private method
//
//=======================================================

// ------------------------------------------------------
/// 現在のテーマを返す
- (CETheme *)theme
// ------------------------------------------------------
{
    return [(NSTextView<CETextViewProtocol> *)[[self layoutManager] firstTextView] theme];
}


// ------------------------------------------------------
/// 保持しているカラーリング辞書から補完文字列配列を生成
- (void)setCompletionWordsFromColoringDictionary
// ------------------------------------------------------
{
    if ([self coloringDictionary] == nil) { return; }
    
    NSMutableArray *completionWords = [NSMutableArray array];
    NSMutableString *firstCharsString = [NSMutableString string];
    NSArray *completionDicts = [self coloringDictionary][k_SCKey_completionsArray];
    
    if (completionDicts) {
        for (NSDictionary *dict in completionDicts) {
            NSString *word = dict[k_SCKey_arrayKeyString];
            [completionWords addObject:word];
            [firstCharsString appendString:[word substringToIndex:1]];
        }
        
    } else {
        NSCharacterSet *trimCharSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
        for (NSString *key in kSyntaxDictKeys) {
            @autoreleasepool {
                for (NSDictionary *wordDict in [self coloringDictionary][key]) {
                    NSString *begin = [wordDict[k_SCKey_beginString] stringByTrimmingCharactersInSet:trimCharSet];
                    NSString *end = [wordDict[k_SCKey_endString] stringByTrimmingCharactersInSet:trimCharSet];
                    if (([begin length] > 0) && ([end length] == 0) && ![wordDict[k_SCKey_regularExpression] boolValue]) {
                        [completionWords addObject:begin];
                        [firstCharsString appendString:[begin substringToIndex:1]];
                    }
                }
            } // ==== end-autoreleasepool
        }
        // ソート
        [completionWords sortedArrayUsingSelector:@selector(compare:)];
    }
    // completionWords を保持する
    [self setCompletionWords:completionWords];
    
    // firstCompletionCharacterSet を保持する
    if ([firstCharsString length] > 0) {
        NSCharacterSet *charSet = [NSCharacterSet characterSetWithCharactersInString:firstCharsString];
        [self setFirstCompletionCharacterSet:charSet];
    } else {
        [self setFirstCompletionCharacterSet:nil];
    }
}


// ------------------------------------------------------
/// 保持しているカラーリング辞書から単純文字列検索のときに使う characterSet の辞書を生成
- (void)setSimpleWordsCharacterSet
// ------------------------------------------------------
{
    if ([self coloringDictionary] == nil) { return; }
    
    NSMutableDictionary *characterSets = [NSMutableDictionary dictionary];
    NSCharacterSet *trimCharSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    
    for (NSString *key in kSyntaxDictKeys) {
        @autoreleasepool {
            NSMutableCharacterSet *charSet = [NSMutableCharacterSet characterSetWithCharactersInString:k_allAlphabetChars];
            
            for (NSDictionary *wordDict in [self coloringDictionary][key]) {
                NSString *begin = [wordDict[k_SCKey_beginString] stringByTrimmingCharactersInSet:trimCharSet];
                NSString *end = [wordDict[k_SCKey_endString] stringByTrimmingCharactersInSet:trimCharSet];
                BOOL isRegex = [wordDict[k_SCKey_regularExpression] boolValue];
                
                if ([begin length] > 0 && [end length] == 0 && !isRegex) {
                    if ([wordDict[k_SCKey_ignoreCase] boolValue]) {
                        [charSet addCharactersInString:[begin uppercaseString]];
                        [charSet addCharactersInString:[begin lowercaseString]];
                    } else {
                        [charSet addCharactersInString:begin];
                    }
                }
            }
            [charSet removeCharactersInString:@"\n\t "];  // 改行、タブ、スペースは無視
            
            characterSets[key] = charSet;
        } // ==== end-autoreleasepool
    }
    
    [self setSimpleWordsCharacterSets:characterSets];
}


// ------------------------------------------------------
/// 指定された文字列をそのまま検索し、カラーリング
- (void)setAttrToSimpleWordsDict:(NSDictionary *)wordsDict ignoreCaseDict:(NSDictionary *)icWordsDict charSet:(NSCharacterSet *)charSet
// ------------------------------------------------------
{
    NSArray *ranges = [self rangesSimpleWordsDict:wordsDict ignoreCaseDict:(NSDictionary *)icWordsDict charSet:charSet];

    for (NSValue *value in ranges) {
        NSRange range = [value rangeValue];
        range.location += [self updateRange].location;

        [self applyTextColor:[self textColor] range:range];
    }
}


// ------------------------------------------------------
/// 指定された文字列をそのまま検索し、位置を返す
- (NSArray *)rangesSimpleWordsDict:(NSDictionary *)wordsDict ignoreCaseDict:(NSDictionary *)icWordsDict charSet:(NSCharacterSet *)charSet
// ------------------------------------------------------
{
    NSMutableArray *ranges = [NSMutableArray array];
    
    NSScanner *scanner = [NSScanner scannerWithString:[self localString]];
    NSString *scannedString = nil;
    
    [scanner setCharactersToBeSkipped:[NSCharacterSet characterSetWithCharactersInString:@"\n\t "]];
    [scanner setCaseSensitive:YES];

    @try {
        while (![scanner isAtEnd]) {
            [scanner scanUpToCharactersFromSet:charSet intoString:NULL];
            if ([scanner scanCharactersFromSet:charSet intoString:&scannedString]) {
                NSUInteger length = [scannedString length];
                
                if (length > 0) {
                    NSUInteger location = [scanner scanLocation];
                    NSArray *words = wordsDict[@(length)];
                    
                    BOOL isFound = [words containsObject:scannedString];
                    
                    if (!isFound) {
                        words = icWordsDict[@(length)];
                        for (NSString *word in words) {
                            if ([word caseInsensitiveCompare:scannedString] == NSOrderedSame) {
                                isFound = YES;
                                break;
                            }
                        }
                    }
                    
                    if (isFound) {
                        NSRange range = NSMakeRange(location - length, length);
                        [ranges addObject:[NSValue valueWithRange:range]];
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        // 何もしない
        NSLog(@"ERROR in \"%s\", reason: %@", __PRETTY_FUNCTION__, [exception reason]);
        return nil;
    }

    return ranges;
}


// ------------------------------------------------------
/// 指定された開始／終了ペアの文字列を検索し、位置を返す
- (NSArray *)rangesBeginString:(NSString *)beginString endString:(NSString *)endString ignoreCase:(BOOL)ignoreCase
                    doColoring:(BOOL)doColoring pairStringKind:(NSUInteger)pairKind
// ------------------------------------------------------
{
    NSString *ESCheckStr = nil;
    NSScanner *scanner = [NSScanner scannerWithString:[self localString]];
    NSUInteger localLength = [[self localString] length];
    NSUInteger start = 0, ESNum = 0, end = 0;
    NSUInteger beginLength = 0, endLength = 0, ESCheckLength;
    NSUInteger startEnd = 0;
    NSRange attrRange, tmpRange;

    beginLength = [beginString length];
    if (beginLength < 1) { return nil; }
    endLength = [endString length];
    [scanner setCharactersToBeSkipped:nil];
    [scanner setCaseSensitive:!ignoreCase];
    NSMutableArray *ranges = [[NSMutableArray alloc] initWithCapacity:10];
    NSInteger i = 0;

    while (![scanner isAtEnd]) {
        [scanner scanUpToString:beginString intoString:nil];
        start = [scanner scanLocation];
        if (start + beginLength < localLength) {
            [scanner setScanLocation:(start + beginLength)];
            ESCheckLength = (start < k_ESCheckLength) ? start : k_ESCheckLength;
            tmpRange = NSMakeRange(start - ESCheckLength, ESCheckLength);
            ESCheckStr = [[self localString] substringWithRange:tmpRange];
            ESNum = [self numberOfEscapeSequenceInString:ESCheckStr];
            if (ESNum % 2 == 1) {
                continue;
            }
            if (!doColoring) {
                startEnd = (pairKind >= k_QC_CommentBaseNum) ? k_QC_Start : k_notUseStartEnd;
                [ranges addObject:@{k_QCPosition: @(start),
                                      k_QCPairKind: @(pairKind),
                                      k_QCStartEnd: @(startEnd),
                                      k_QCStrLength: @(beginLength)}];
            }
        } else {
            break;
        }
        while (1) {
            i++;
            if ((i % 10 == 0) && [[self indicatorController] isCancelled]) {
                return nil;
            }
            [scanner scanUpToString:endString intoString:nil];
            end = [scanner scanLocation] + endLength;
            if (end <= localLength) {
                [scanner setScanLocation:end];
                ESCheckLength = ((end - endLength) < k_ESCheckLength) ? (end - endLength) : k_ESCheckLength;
                tmpRange = NSMakeRange(end - endLength - ESCheckLength, ESCheckLength);
                ESCheckStr = [[self localString] substringWithRange:tmpRange];
                ESNum = [self numberOfEscapeSequenceInString:ESCheckStr];
                if (ESNum % 2 == 1) {
                    continue;
                } else {
                    if (start < end) {
                        if (doColoring) {
                            attrRange = NSMakeRange(start, end - start);
                            [ranges addObject:[NSValue valueWithRange:attrRange]];
                        } else {
                            startEnd = (pairKind >= k_QC_CommentBaseNum) ? k_QC_End : k_notUseStartEnd;
                            [ranges addObject:@{k_QCPosition: @(end - endLength),
                                                  k_QCPairKind: @(pairKind),
                                                  k_QCStartEnd: @(startEnd),
                                                  k_QCStrLength: @(endLength)}];
                        }
                        break;
                    }
                }
            } else {
                break;
            }
        } // end-while (1)
    } // end-while (![scanner isAtEnd])
    return ranges;
}


// ------------------------------------------------------
/// 指定された文字列を正規表現として検索し、位置を返す
- (NSArray *)rangesRegularExpressionString:(NSString *)regexStr ignoreCase:(BOOL)ignoreCase
                                doColoring:(BOOL)doColoring pairStringKind:(NSUInteger)pairKind
// ------------------------------------------------------
{
    __block NSMutableArray *ranges = [NSMutableArray array];
    NSString *string = [self localString];
    uint32_t options = (ignoreCase) ? (RKLCaseless | RKLMultiline) : RKLMultiline;
    NSError *error = nil;
    
    [string enumerateStringsMatchedByRegex:regexStr
                                   options:options
                                   inRange:NSMakeRange(0, [string length])
                                     error:&error
                        enumerationOptions:RKLRegexEnumerationCapturedStringsNotRequired
                                usingBlock:^(NSInteger captureCount,
                                             NSString *const __unsafe_unretained *capturedStrings,
                                             const NSRange *capturedRanges,
                                             volatile BOOL *const stop)
     {
         NSRange attrRange = capturedRanges[0];
         
         if (doColoring) {
             [ranges addObject:[NSValue valueWithRange:attrRange]];
             
         } else {
             if ([[self indicatorController] isCancelled]) {
                 *stop = YES;
                 return;
             }
             
             NSUInteger QCStart = 0, QCEnd = 0;
             
             if (pairKind >= k_QC_CommentBaseNum) {
                 QCStart = k_QC_Start;
                 QCEnd = k_QC_End;
             } else {
                 QCStart = QCEnd = k_notUseStartEnd;
             }
             [ranges addObject:@{k_QCPosition: @(attrRange.location),
                                   k_QCPairKind: @(pairKind),
                                   k_QCStartEnd: @(QCStart),
                                   k_QCStrLength: @0U}];
             [ranges addObject:@{k_QCPosition: @(NSMaxRange(attrRange)),
                                   k_QCPairKind: @(pairKind),
                                   k_QCStartEnd: @(QCEnd),
                                   k_QCStrLength: @0U}];
         }
     }];
    
    if (error && ![[error userInfo][RKLICURegexErrorNameErrorKey] isEqualToString:@"U_ZERO_ERROR"]) {
        // 何もしない
        NSLog(@"ERROR: %@", [error localizedDescription]);
        return nil;
    }
    
    return ranges;
}


// ------------------------------------------------------
/// 指定された開始／終了文字列を正規表現として検索し、位置を返す
- (NSArray *)rangesRegularExpressionBeginString:(NSString *)beginString endString:(NSString *)endString ignoreCase:(BOOL)ignoreCase
                                     doColoring:(BOOL)doColoring pairStringKind:(NSUInteger)pairKind
// ------------------------------------------------------
{
    __block NSMutableArray *ranges = [NSMutableArray array];
    NSString *string = [self localString];
    uint32_t options = (ignoreCase) ? (RKLCaseless | RKLMultiline) : RKLMultiline;
    NSError *error = nil;
    
    [string enumerateStringsMatchedByRegex:beginString
                                   options:options
                                   inRange:NSMakeRange(0, [string length])
                                     error:&error
                        enumerationOptions:RKLRegexEnumerationCapturedStringsNotRequired
                                usingBlock:^(NSInteger captureCount,
                                             NSString *const __unsafe_unretained *capturedStrings,
                                             const NSRange *capturedRanges,
                                             volatile BOOL *const stop)
     {
         if ([[self indicatorController] isCancelled]) {
             *stop = YES;
             return;
         }
         
         NSRange beginRange = capturedRanges[0];
         NSRange endRange = [string rangeOfRegex:endString
                                         options:options
                                         inRange:NSMakeRange(NSMaxRange(beginRange),
                                                             [string length] - NSMaxRange(beginRange))
                                         capture:0
                                           error:nil];
         
         if (endRange.location == NSNotFound) {
             return;
         }
         
         NSRange attrRange = NSUnionRange(beginRange, endRange);
         
         if (doColoring) {
             [ranges addObject:[NSValue valueWithRange:attrRange]];
             
         } else {
             NSUInteger QCStart = 0, QCEnd = 0;
             if (pairKind >= k_QC_CommentBaseNum) {
                 QCStart = k_QC_Start;
                 QCEnd = k_QC_End;
             } else {
                 QCStart = QCEnd = k_notUseStartEnd;
             }
             [ranges addObject:@{k_QCPosition: @(attrRange.location),
                                   k_QCPairKind: @(pairKind),
                                   k_QCStartEnd: @(QCStart),
                                   k_QCStrLength: @0U}];
             [ranges addObject:@{k_QCPosition: @(NSMaxRange(attrRange)),
                                   k_QCPairKind: @(pairKind),
                                   k_QCStartEnd: @(QCEnd),
                                   k_QCStrLength: @0U}];
         }
     }];
    
    if (error && ![[error userInfo][RKLICURegexErrorNameErrorKey] isEqualToString:@"U_ZERO_ERROR"]) {
        // 何もしない
        NSLog(@"ERROR: %@", [error localizedDescription]);
        return nil;
    }
    
    return ranges;
}


// ------------------------------------------------------
/// コメントをカラーリング
- (void)setAttrToCommentsWithSyntaxArray:(NSArray *)syntaxArray
                            singleQuotes:(BOOL)withSingleQuotes doubleQuotes:(BOOL)withDoubleQuotes
                         updateIndicator:(BOOL)updateIndicator
// ------------------------------------------------------
{
    NSMutableArray *posArray = [NSMutableArray array];
    NSMutableDictionary *simpleWordsDict = [NSMutableDictionary dictionaryWithCapacity:40];
    NSMutableDictionary *simpleICWordsDict = [NSMutableDictionary dictionaryWithCapacity:40];
    NSArray *tmpArray = nil;
    NSDictionary *strDict, *curRecord, *checkRecord;
    NSColor *color;
    NSString *beginStr = nil, *endStr = nil;
    BOOL ignoresCase = NO;
    NSRange coloringRange;
    NSInteger i, j, index = 0, syntaxCount = [syntaxArray count], coloringCount;
    NSUInteger QCKind, start, end, checkStartEnd;
    BOOL hasEnd = NO;

    // コメント定義の位置配列を生成
    for (i = 0; i < syntaxCount; i++) {
        if ((i % 10 == 0) && [[self indicatorController] isCancelled]) { return; }
        strDict = syntaxArray[i];
        ignoresCase = [strDict[k_SCKey_ignoreCase] boolValue];
        beginStr = strDict[k_SCKey_beginString];

        if ([beginStr length] < 1) { continue; }

        endStr = strDict[k_SCKey_endString];

        if ([strDict[k_SCKey_regularExpression] boolValue]) {
            if (endStr && ([endStr length] > 0)) {
                tmpArray = [self rangesRegularExpressionBeginString:beginStr
                                                          endString:endStr
                                                         ignoreCase:ignoresCase
                                                         doColoring:NO
                                                     pairStringKind:(k_QC_CommentBaseNum + i)];
                [posArray addObjectsFromArray:tmpArray];
            } else {
                tmpArray = [self rangesRegularExpressionString:beginStr
                                                    ignoreCase:ignoresCase
                                                    doColoring:NO
                                                pairStringKind:(k_QC_CommentBaseNum + i)];
                [posArray addObjectsFromArray:tmpArray];
            }
        } else {
            if (endStr && ([endStr length] > 0)) {
                tmpArray = [self rangesBeginString:beginStr
                                     endString:endStr
                                    ignoreCase:ignoresCase
                                        doColoring:NO
                                    pairStringKind:(k_QC_CommentBaseNum + i)];
                [posArray addObjectsFromArray:tmpArray];
            } else {
                NSNumber *len = @([beginStr length]);
                NSMutableDictionary *dict = ignoresCase ? simpleICWordsDict : simpleWordsDict;
                NSMutableArray *wordsArray = dict[len];
                if (wordsArray) {
                    [wordsArray addObject:beginStr];
                } else {
                    wordsArray = [NSMutableArray arrayWithObject:beginStr];
                    dict[len] = wordsArray;
                }
            }
        }
    } // end-for
    // シングルクォート定義があれば位置配列を生成、マージ
    if (withSingleQuotes) {
        [posArray addObjectsFromArray:[self rangesBeginString:@"\'" endString:@"\'" ignoreCase:NO
                                                   doColoring:NO pairStringKind:k_QC_SingleQ]];
    }
    // ダブルクォート定義があれば位置配列を生成、マージ
    if (withDoubleQuotes) {
        [posArray addObjectsFromArray:[self rangesBeginString:@"\"" endString:@"\"" ignoreCase:NO
                                                   doColoring:NO pairStringKind:k_QC_DoubleQ]];
    }
    // コメントもクォートもなければ、もどる
    if (([posArray count] < 1) && ([simpleWordsDict count] < 1)) { return; }

    // まず、開始文字列だけのコメント定義があればカラーリング
    if (([simpleWordsDict count]) > 0) {
        [self setAttrToSimpleWordsDict:simpleWordsDict
                        ignoreCaseDict:simpleICWordsDict
                               charSet:[self simpleWordsCharacterSets][k_SCKey_commentsArray]];
    }

    // カラーリング対象がなければ、もどる
    if ([posArray count] < 1) { return; }
    NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:k_QCPosition ascending:YES];
    [posArray sortUsingDescriptors:@[descriptor]];
    coloringCount = [posArray count];

    QCKind = k_notUseKind;
    while (index < coloringCount) {
        // インジケータ更新
        if (updateIndicator && (index % 10 == 0)) {
            [[self indicatorController] progressIndicator:10.0 * 200 / coloringCount];
        }
        curRecord = posArray[index];
        if (QCKind == k_notUseKind) {
            if ([curRecord[k_QCStartEnd] unsignedIntegerValue] == k_QC_End) {
                index++;
                continue;
            }
            QCKind = [curRecord[k_QCPairKind] unsignedIntegerValue];
            start = [curRecord[k_QCPosition] unsignedIntegerValue];
            index++;
            continue;
        }
        if (QCKind == [curRecord[k_QCPairKind] unsignedIntegerValue]) {
            if (QCKind == k_QC_SingleQ) {
                color = [self singleQuotesColor];
            } else if (QCKind == k_QC_DoubleQ) {
                color = [self doubleQuotesColor];
            } else if (QCKind >= k_QC_CommentBaseNum) {
                color = [self textColor];
            } else {
                NSLog(@"%s \n Can not set Attrs.", __PRETTY_FUNCTION__);
                break;
            }
            end = [curRecord[k_QCPosition] unsignedIntegerValue] +
                  [curRecord[k_QCStrLength] unsignedIntegerValue];
            coloringRange = NSMakeRange(start + [self updateRange].location, end - start);
            [self applyTextColor:color range:coloringRange];
            QCKind = k_notUseKind;
            index++;
        } else {
            // 「終わり」があるか調べる
            for (j = (index + 1); j < coloringCount; j++) {
                checkRecord = posArray[j];
                if (QCKind == [checkRecord[k_QCPairKind] unsignedIntegerValue]) {
                    checkStartEnd = [checkRecord[k_QCStartEnd] unsignedIntegerValue];
                    if ((checkStartEnd == k_notUseStartEnd) || (checkStartEnd == k_QC_End)) {
                        hasEnd = YES;
                        break;
                    }
                }
                hasEnd = NO;
            }
            // 「終わり」があればそこへジャンプ、なければ最後までカラーリングして、抜ける
            if (hasEnd) {
                index = j;
            } else {
                if (QCKind == k_QC_SingleQ) {
                    color = [self singleQuotesColor];
                } else if (QCKind == k_QC_DoubleQ) {
                    color = [self doubleQuotesColor];
                } else if (QCKind >= k_QC_CommentBaseNum) {
                    color = [self textColor];
                } else {
                    NSLog(@"%s \n Can not set Attrs.", __PRETTY_FUNCTION__);
                    break;
                }
                coloringRange = NSMakeRange(start + [self updateRange].location, NSMaxRange([self updateRange]) - start);
                [self applyTextColor:color range:coloringRange];
                break;
            }
        }
    }
}


// ------------------------------------------------------
/// 与えられた文字列の末尾にエスケープシーケンス（バックスラッシュ）がいくつあるかを返す
- (NSUInteger)numberOfEscapeSequenceInString:(NSString *)string
// ------------------------------------------------------
{
    NSUInteger count = 0;

    for (NSInteger i = [string length] - 1; i >= 0; i--) {
        if ([string characterAtIndex:i] == '\\') {
            count++;
        } else {
            break;
        }
    }
    return count;
}


// ------------------------------------------------------
/// 不可視文字表示時に文字色を変更する
- (void)applyColorToOtherInvisibleChars
// ------------------------------------------------------
{
    if (![[self layoutManager] showOtherInvisibles]) { return; }
    NSColor *color = [[self theme] invisiblesColor];
    if ([[self theme] textColor] == color) { return; }
    NSMutableArray *ranges = [NSMutableArray array];
    NSScanner *scanner = [NSScanner scannerWithString:[self localString]];
    NSString *controlStr;
    NSRange coloringRange;
    NSInteger start;

    while (![scanner isAtEnd]) {
        [scanner scanUpToCharactersFromSet:[NSCharacterSet controlCharacterSet] intoString:nil];
        start = [scanner scanLocation];
        if ([scanner scanCharactersFromSet:[NSCharacterSet controlCharacterSet] intoString:&controlStr]) {
            [ranges addObject:[NSValue valueWithRange:NSMakeRange(start, [controlStr length])]];
        }
    }
    
    for (NSValue *value in ranges) {
        coloringRange = [value rangeValue];
        coloringRange.location += [self updateRange].location;
        
        [self applyTextColor:color range:coloringRange];
    }
}


// ------------------------------------------------------
/// カラーリングを実行
- (void)doColoring
// ------------------------------------------------------
{
    if ([[self wholeString] length] == 0) { return; }
    [self setLocalString:[[self wholeString] substringWithRange:[self updateRange]]]; // カラーリング対象文字列を保持
    if ([[self localString] length] == 0) { return; }

    // 現在あるカラーリングを削除
    [self clearTextColorsInRange:[self updateRange]];
    
    // カラーリング不要なら不可視文字のカラーリングだけして戻る
    if (([[self coloringDictionary][k_SCKey_numOfObjInArray] integerValue] == 0) ||
        ([[self syntaxStyleName] isEqualToString:NSLocalizedString(@"None", @"")]))
    {
        [self applyColorToOtherInvisibleChars];
        return;
    }
    
    NSWindow *documentWindow = [self isPrinting] ? nil : [[[self layoutManager] firstTextView] window];
    
    // 規定の文字数以上の場合にはカラーリングインジケータシートを表示
    // （ただし、k_key_showColoringIndicatorTextLength が「0」の時は表示しない）
    NSUInteger indicatorThreshold = [[NSUserDefaults standardUserDefaults] integerForKey:k_key_showColoringIndicatorTextLength];
    if (![self isPrinting] && (indicatorThreshold > 0) && ([self updateRange].length > indicatorThreshold)) {
        [self setIndicatorController:[[CEIndicatorSheetController alloc] initWithMessage:NSLocalizedString(@"Coloring text...", nil)]];
        [[self indicatorController] beginSheetForWindow:documentWindow];
    }
    
    NSMutableDictionary *simpleWordsDict = [NSMutableDictionary dictionaryWithCapacity:40];
    NSMutableDictionary *simpleICWordsDict = [NSMutableDictionary dictionaryWithCapacity:40];
    BOOL isSingleQuotes = NO, isDoubleQuotes = NO;
    NSUInteger count;
    
    @try {
        // Keywords > Commands > Categories > Variables > Values > Numbers > Strings > Characters > Comments
        for (NSString *syntaxKey in kSyntaxDictKeys) {
            
            // キャンセルされたら、現在あるカラーリング（途中まで色づけられたもの）を削除して戻る
            if ([[self indicatorController] isCancelled]) {
                [self clearTextColorsInRange:[self updateRange]];
                
                if (![self isPrinting]) {
                    [[[CEDocumentController sharedDocumentController] documentForWindow:documentWindow]
                     doSetSyntaxStyle:NSLocalizedString(@"None", @"") delay:YES];
                }
                break;
            }
            
            NSArray *strDicts = [self coloringDictionary][syntaxKey];
            if (!strDicts) {
                continue;
            }
            count = [strDicts count];
            [self setTextColor:[[self theme] syntaxColorWithSyntaxKey:syntaxKey]]; // ===== retain

            // シングル／ダブルクォートのカラーリングがあったら、コメントとともに別メソッドでカラーリングする
            if ([syntaxKey isEqualToString:k_SCKey_commentsArray]) {
                [self setAttrToCommentsWithSyntaxArray:strDicts singleQuotes:isSingleQuotes
                                          doubleQuotes:isDoubleQuotes updateIndicator:([self indicatorController])];
                [self setTextColor:nil]; // ===== release
                break;
            }
            if (count < 1) {
                if ([self indicatorController]) {
                    [[self indicatorController] progressIndicator:100.0];
                }
                continue;
            }

            NSMutableArray *targetArray = [[NSMutableArray alloc] initWithCapacity:10];
            NSArray *tmpArray = nil;
            NSUInteger i = 0;
            for (NSDictionary *strDict in strDicts) {
                @autoreleasepool {
                    BOOL ignoresCase = [strDict[k_SCKey_ignoreCase] boolValue];
                    NSString *beginStr = strDict[k_SCKey_beginString];

                    if ([beginStr length] == 0) { continue; }

                    NSString *endStr = strDict[k_SCKey_endString];

                    if ([strDict[k_SCKey_regularExpression] boolValue]) {
                        if ([endStr length] > 0) {
                            tmpArray = [self rangesRegularExpressionBeginString:beginStr
                                                                      endString:endStr
                                                                     ignoreCase:ignoresCase
                                                                     doColoring:YES
                                                                 pairStringKind:k_notUseKind];
                            if (tmpArray) {
                                [targetArray addObject:tmpArray];
                            }
                        } else {
                            tmpArray = [self rangesRegularExpressionString:beginStr
                                                                ignoreCase:ignoresCase
                                                                doColoring:YES
                                                            pairStringKind:k_notUseKind];
                            if (tmpArray) {
                                [targetArray addObject:tmpArray];
                            }
                        }
                    } else {
                        if ([endStr length] > 0) {
                            // 開始／終了ともに入力されていたらクォートかどうかをチェック、最初に出てきたクォートのみを把握
                            if ([beginStr isEqualToString:@"'"] && [endStr isEqualToString:@"'"]) {
                                if (!isSingleQuotes) {
                                    isSingleQuotes = YES;
                                    [self setSingleQuotesColor:[self textColor]]; // ===== retain
                                }
                                continue;
                            }
                            if ([beginStr isEqualToString:@"\""] && [endStr isEqualToString:@"\""]) {
                                if (!isDoubleQuotes) {
                                    isDoubleQuotes = YES;
                                    [self setDoubleQuotesColor:[self textColor]]; // ===== retain
                                }
                                continue;
                            }
                            tmpArray = [self rangesBeginString:beginStr endString:endStr ignoreCase:ignoresCase
                                                    doColoring:YES pairStringKind:k_notUseKind];
                            if (tmpArray) {
                                [targetArray addObject:tmpArray];
                            }
                        } else {
                            NSNumber *len = @([beginStr length]);
                            NSMutableDictionary *dict = ignoresCase ? simpleICWordsDict : simpleWordsDict;
                            NSMutableArray *wordsArray = dict[len];
                            if (wordsArray) {
                                [wordsArray addObject:beginStr];
                                
                            } else {
                                wordsArray = [NSMutableArray arrayWithObject:beginStr];
                                dict[len] = wordsArray;
                            }
                        }
                    }
                    // インジケータ更新
                    if ([self indicatorController]) {
                        if (i % 10 == 0) {
                            [[self indicatorController] progressIndicator:10.0 * k_perCompoIncrement / count];
                        }
                        i++;
                    }
                } // ==== end-autoreleasepool
            } // end-for (i)
            if (([simpleWordsDict count]) > 0) {
                tmpArray = [self rangesSimpleWordsDict:simpleWordsDict
                                        ignoreCaseDict:simpleICWordsDict
                                               charSet:[self simpleWordsCharacterSets][syntaxKey]];
                if (tmpArray) {
                    [targetArray addObject:tmpArray];
                }
                [simpleWordsDict removeAllObjects];
            }
            // カラーリング実行
            for (NSArray *ranges in targetArray) {
                for (NSValue *value in ranges) {
                    NSRange range = [value rangeValue];
                    range.location += [self updateRange].location;
                    
                    [self applyTextColor:[self textColor] range:range];
                }
            }
            if ([self indicatorController]) {
                [[self indicatorController] progressIndicator:100.0];
            }
            [self setTextColor:nil];  // ===== release
        } // end-for (syntaxKey)
        [self applyColorToOtherInvisibleChars];
    } @catch (NSException *exception) {
        // 何もしない
        NSLog(@"ERROR in \"%s\" reason: %@", __PRETTY_FUNCTION__, [exception reason]);
    }

    // インジーケータシートを片づける
    if ([self indicatorController]) {
        [[self indicatorController] endSheet];
        [self setIndicatorController:nil];
    }
    
    // 不要な変数を片づける
    [self setLocalString:nil];
}


// ------------------------------------------------------
/// 指定した範囲のテキストに色をつける
- (void)applyTextColor:(NSColor *)color range:(NSRange)range
// ------------------------------------------------------
{
    if ([self isPrinting]) {
        [[[self layoutManager] firstTextView] setTextColor:color range:range];
    } else {
        [[self layoutManager] addTemporaryAttribute:NSForegroundColorAttributeName
                                              value:color forCharacterRange:range];
    }
}


// ------------------------------------------------------
/// 現在付いている色を解除する
- (void)clearTextColorsInRange:(NSRange)range
// ------------------------------------------------------
{
    if ([self isPrinting]) {
        [[[self layoutManager] firstTextView] setTextColor:nil range:range];
    } else {
        [[self layoutManager] removeTemporaryAttribute:NSForegroundColorAttributeName
                                     forCharacterRange:range];
    }
}

@end
