#import "PHAssetsService.h"
#import <React/RCTConvert.h>
#import "RCTConvert+RNPhotosFramework.h"
#import "PHFetchOptionsService.h"
#import "PHChangeObserver.h"
#import "PHHelpers.h"
#import <React/RCTConvert.h>
#import <React/RCTProfile.h>
#import "PHAssetWithCollectionIndex.h"

@import Photos;
@implementation PHAssetsService

+(PHFetchResult<PHAsset *> *) getAssetsForParams:(NSDictionary *)params  {
    NSString * cacheKey = [RCTConvert NSString:params[@"_cacheKey"]];
    NSString * albumLocalIdentifier = [RCTConvert NSString:params[@"albumLocalIdentifier"]];

    if(cacheKey != nil) {
        RCTCachedFetchResult *cachedResultSet = [[PHChangeObserver sharedChangeObserver] getFetchResultFromCacheWithuuid:cacheKey];
        if(cachedResultSet != nil) {
            return [cachedResultSet fetchResult];
        }
    }

    PHFetchResult<PHAsset *> *fetchResult;
    if(albumLocalIdentifier != nil) {
        fetchResult = [self getAssetsForParams:params andAlbumLocalIdentifier:albumLocalIdentifier];
    }
    if(fetchResult == nil) {
        fetchResult = [PHAssetsService getAllAssetsForParams:params];
    }

    if(cacheKey != nil && fetchResult != nil) {
        [[PHChangeObserver sharedChangeObserver] cacheFetchResultWithUUID:fetchResult andObjectType:[PHAsset class] andUUID:cacheKey andOrginalFetchParams:params];
    }

    return fetchResult;
}

+(PHFetchResult<PHAsset *> *)getAssetsForParams:(NSDictionary *)params andAlbumLocalIdentifier:(NSString *)albumLocalIdentifier {
    PHFetchOptions *options = [PHFetchOptionsService getAssetFetchOptionsFromParams:params];
    PHFetchResult<PHAssetCollection *> *collections = [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[albumLocalIdentifier] options:nil];

    PHFetchResult<PHAsset *> * assets = [PHAsset fetchAssetsInAssetCollection:collections.firstObject options:options];
    return assets;
}

+(PHFetchResult<PHAsset *> *) getAssetsFromArrayOfLocalIdentifiers:(NSArray<NSString *> *)arrayWithLocalIdentifiers {
    return [PHAsset fetchAssetsWithLocalIdentifiers:arrayWithLocalIdentifiers options:nil];
}

+(PHFetchResult<PHAsset *> *) getAllAssetsForParams:(NSDictionary *)params {
    PHFetchOptions *options = [PHFetchOptionsService getAssetFetchOptionsFromParams:params];
    return [PHAsset fetchAssetsWithOptions:options];
}

+(NSArray<NSDictionary *> *) assetsArrayToUriArray:(NSArray<id> *)assetsArray andIncludeMetaData:(BOOL)includeMetaData {
    RCT_PROFILE_BEGIN_EVENT(0, @"-[RCTCameraRollRNPhotosFrameworkManager assetsArrayToUriArray", nil);

    NSMutableArray *uriArray = [NSMutableArray arrayWithCapacity:assetsArray.count];
    NSDictionary *reveredMediaTypes = [RCTConvert PHAssetMediaTypeValuesReversed];
    for(int i = 0;i < assetsArray.count; i++) {
        id assetObj = [assetsArray objectAtIndex:i];
        NSNumber *assetIndex = (NSNumber *)[NSNull null];
        PHAsset *asset;
        if([assetObj isKindOfClass:[PHAsset class]]) {
            asset = assetObj;
        }else {
            PHAssetWithCollectionIndex *assetWithCollectionIndex = assetObj;
            asset = assetWithCollectionIndex.asset;
            assetIndex = assetWithCollectionIndex.collectionIndex;
        }

        NSMutableDictionary *responseDict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                             [asset localIdentifier], @"localIdentifier",
                                             @([asset pixelWidth]), @"width",
                                             @([asset pixelHeight]), @"height",
                                             nil];
//        if(includeMetaData) {
//            [self extendAssetDicWithAssetMetaData:responseDict andPHAsset:asset];
//        }

        [responseDict setObject:@([PHHelpers getTimeSince1970:[asset creationDate]]) forKey:@"creationDate"];

        [uriArray addObject:responseDict];
    }
    RCT_PROFILE_END_EVENT(RCTProfileTagAlways, @"");

    return uriArray;
}

+(NSMutableDictionary *)extendAssetDicWithAssetMetaData:(NSMutableDictionary *)dictToExtend andPHAsset:(PHAsset *)asset {
    [dictToExtend setObject:@([PHHelpers getTimeSince1970:[asset creationDate]]) forKey:@"creationDate"];
    [dictToExtend setObject:@([PHHelpers getTimeSince1970:[asset modificationDate]])forKey:@"modificationDate"];
    [dictToExtend setObject:[PHHelpers CLLocationToJson:[asset location]] forKey:@"location"];
    [dictToExtend setObject:[PHHelpers nsOptionsToArray:[asset mediaSubtypes] andBitSize:32 andReversedEnumDict:[RCTConvert PHAssetMediaSubtypeValuesReversed]] forKey:@"mediaSubTypes"];
    [dictToExtend setObject:@([asset isFavorite]) forKey:@"isFavorite"];
    [dictToExtend setObject:@([asset isHidden]) forKey:@"isHidden"];
    if ([asset respondsToSelector:@selector(sourceType)]) {
        // not supported in iOS 8
        [dictToExtend setObject:[PHHelpers nsOptionsToValue:[asset sourceType] andBitSize:32 andReversedEnumDict:[RCTConvert PHAssetSourceTypeValuesReversed]] forKey:@"sourceType"];
    }
    NSString *burstIdentifier = [asset burstIdentifier];
    if(burstIdentifier != nil) {
        [dictToExtend setObject:burstIdentifier forKey:@"burstIdentifier"];
        [dictToExtend setObject:@([asset representsBurst]) forKey:@"representsBurst"];
        [dictToExtend setObject:[PHHelpers nsOptionsToArray:[asset burstSelectionTypes] andBitSize:32 andReversedEnumDict:[RCTConvert PHAssetBurstSelectionTypeValuesReversed]] forKey:@"burstSelectionTypes"];
    }
    if([asset mediaType] == PHAssetMediaTypeVideo || [asset mediaType] == PHAssetMediaTypeAudio) {
        [dictToExtend setObject:@([asset duration]) forKey:@"duration"];
    }
    return dictToExtend;
}

+(NSMutableArray<PHAssetWithCollectionIndex*> *) getAssetsForFetchResult:(PHFetchResult *)assetsFetchResult startIndex:(int)startIndex endIndex:(int)endIndex assetDisplayStartToEnd:(BOOL)assetDisplayStartToEnd andAssetDisplayBottomUp:(BOOL)assetDisplayBottomUp {

    NSMutableArray<PHAssetWithCollectionIndex *> *assets = [NSMutableArray new];
    int assetCount = (int)assetsFetchResult.count;

    if(assetCount != 0) {

        NSIndexSet *indexSet = [self getIndexSetForAssetEnumerationWithAssetCount:(int)assetsFetchResult.count startIndex:startIndex endIndex:endIndex assetDisplayStartToEnd:assetDisplayStartToEnd];

        NSEnumerationOptions enumerationOptionsStartToEnd = assetDisplayBottomUp ? NSEnumerationReverse : NSEnumerationConcurrent;
        NSEnumerationOptions enumerationOptionsEndToStart = assetDisplayBottomUp ? NSEnumerationConcurrent : NSEnumerationReverse;
        // display assets from the bottom to top of page if assetDisplayBottomUp is true
        NSEnumerationOptions enumerationOptions = assetDisplayStartToEnd ? enumerationOptionsStartToEnd : enumerationOptionsEndToStart;

        [assetsFetchResult enumerateObjectsAtIndexes:indexSet options:enumerationOptions usingBlock:^(PHAsset *asset, NSUInteger idx, BOOL * _Nonnull stop) {
            [assets addObject:[[PHAssetWithCollectionIndex alloc] initWithAsset:asset andCollectionIndex:@(idx)]];
        }];
    }

    return assets;
}

+(NSMutableArray<PHAssetWithCollectionIndex*> *) getAssetsForFetchResult:(PHFetchResult *)assetsFetchResult atIndecies:(NSArray<NSNumber *> *)indecies {
    NSMutableArray<PHAssetWithCollectionIndex *> *assets = [NSMutableArray new];
    NSUInteger assetCount = assetsFetchResult.count;
    for(int i = 0; i < indecies.count; i++) {
        int collectionIndex = [[indecies objectAtIndex:i] intValue];
        if(collectionIndex <= (assetCount - 1) && collectionIndex >= 0) {
            PHAsset *asset = [assetsFetchResult objectAtIndex:collectionIndex];
            [assets addObject:[[PHAssetWithCollectionIndex alloc] initWithAsset:asset andCollectionIndex:@(collectionIndex)]];

        }

    }
    return assets;
}


+(NSIndexSet *) getIndexSetForAssetEnumerationWithAssetCount:(int)assetCount startIndex:(int)startIndex endIndex:(int)endIndex assetDisplayStartToEnd:(BOOL)assetDisplayStartToEnd {
        int originalStartIndex = startIndex;
        int originalEndIndex = endIndex;
        startIndex = (assetCount - endIndex) - 1;
        endIndex = assetCount - originalStartIndex;
        // load oldest assets from library first if assetDisplayStartToEnd is true
        if(assetDisplayStartToEnd) {
            startIndex = originalStartIndex;
            endIndex = originalEndIndex;
        }
        if(startIndex < 0) {
            startIndex = 0;
        }
        if(endIndex < 0) {
            endIndex = 0;
        }
        if(startIndex >= assetCount) {
            startIndex = assetCount;
        }
        if(endIndex >= assetCount) {
            endIndex = assetCount;
        }
        int indexRangeLength = endIndex - startIndex;
        // adjust range length calculation if original and active index are 0
        if(originalStartIndex == 0 && startIndex == 0){
            indexRangeLength = (endIndex - startIndex) + 1;
        }
        if(indexRangeLength >= assetCount){
            indexRangeLength = assetCount;
        }
        return [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(startIndex, indexRangeLength)];
}

+(void)deleteAssets:(PHFetchResult<PHAsset *> *)assetsToDelete andCompleteBLock:(nullable void(^)(BOOL success, NSError *__nullable error, NSArray<NSString *> * localIdentifiers))completeBlock {
    __block NSMutableArray<NSString *> *deletedAssetsLocalIdentifers = [NSMutableArray arrayWithCapacity:assetsToDelete.count];
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        for(int i = 0; i< assetsToDelete.count; i++) {
            PHAsset *assetToDelete = [assetsToDelete objectAtIndex:i];
            BOOL req = [assetToDelete canPerformEditOperation:PHAssetEditOperationDelete];
            if (req) {
                [deletedAssetsLocalIdentifers addObject:assetToDelete.localIdentifier];
                [PHAssetChangeRequest deleteAssets:@[assetToDelete]];
            }
        }
    } completionHandler:^(BOOL success, NSError *error) {
        completeBlock(success, error, deletedAssetsLocalIdentifers);
    }];
}

+(void)requestEditingMetadataWithCompletionBlock:(void(^)(NSDictionary<NSString *,id> * dict))completeBlock andAsset:(PHAsset *)asset{
        PHContentEditingInputRequestOptions *editOptions = [[PHContentEditingInputRequestOptions alloc]init];
        editOptions.networkAccessAllowed = YES;
        [asset requestContentEditingInputWithOptions:editOptions completionHandler:^(PHContentEditingInput *contentEditingInput, NSDictionary *info) {
            CIImage *image = [CIImage imageWithContentsOfURL:contentEditingInput.fullSizeImageURL];
            completeBlock(image.properties);
        }];
}

-(void)requestImageDataWithCompletionBlockAndAsset:(PHAsset *)asset {
    PHImageRequestOptions * imageRequestOptions = [[PHImageRequestOptions alloc] init];
    imageRequestOptions.networkAccessAllowed = YES;
    [[PHImageManager defaultManager]
     requestImageDataForAsset:asset
     options:imageRequestOptions
     resultHandler:^(NSData *imageData, NSString *dataUTI,
                     UIImageOrientation orientation,
                     NSDictionary *info)
     {
         NSLog(@"info = %@", info);
         if ([info objectForKey:@"PHImageFileURLKey"]) {
             // path looks like this -
             // file:///var/mobile/Media/DCIM/###APPLE/IMG_####.JPG
             //NSURL *path = [info objectForKey:@"PHImageFileURLKey"];
         }
     }];
}

+(void)updateLocation:(CLLocation*)location creationDate:(NSDate*)creationDate completionBlock:(void(^)(BOOL success))completionBlock andAsset:(PHAsset *)asset {
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetChangeRequest *assetRequest = [PHAssetChangeRequest changeRequestForAsset:asset];
        if(location) assetRequest.location = location;
        if(creationDate) assetRequest.creationDate = creationDate;
    } completionHandler:^(BOOL success, NSError *error) {
        if(success){
            completionBlock(YES);
        } else {
            completionBlock(NO);
        }
    }];
}


/*+(void)saveImageToCameraRoll:(UIImage*)image location:(CLLocation*)location completionBlock:(PHAssetAssetBoolBlock)completionBlock{
    __block PHObjectPlaceholder *placeholderAsset = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetChangeRequest *newAssetRequest = [PHAssetChangeRequest creationRequestForAssetFromImage:image];
        newAssetRequest.location = location;
        newAssetRequest.creationDate = [NSDate date];
        placeholderAsset = newAssetRequest.placeholderForCreatedAsset;
    } completionHandler:^(BOOL success, NSError *error) {
        if(success){
            PHAsset *asset = [self getAssetFromlocalIdentifier:placeholderAsset.localIdentifier];
            completionBlock(asset, YES);
        } else {
            completionBlock(nil, NO);
        }
    }];
}

+(void)saveVideoAtURL:(NSURL*)url location:(CLLocation*)location completionBlock:(PHAssetAssetBoolBlock)completionBlock{
    __block PHObjectPlaceholder *placeholderAsset = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetChangeRequest *newAssetRequest = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:url];
        newAssetRequest.location = location;
        newAssetRequest.creationDate = [NSDate date];
        placeholderAsset = newAssetRequest.placeholderForCreatedAsset;
    } completionHandler:^(BOOL success, NSError *error) {
        if(success){
            PHAsset *asset = [self getAssetFromlocalIdentifier:placeholderAsset.localIdentifier];
            completionBlock(asset, YES);
        } else {
            completionBlock(nil, NO);
        }
    }];
}*/

@end
