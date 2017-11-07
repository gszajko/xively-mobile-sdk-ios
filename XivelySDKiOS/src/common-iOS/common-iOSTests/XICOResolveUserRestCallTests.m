//
//  XICOGetEndUserRestCallTests.m
//  common-iOS
//
//  Created by vfabian on 30/07/15.
//  Copyright (c) 2015 LogMeIn Inc. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>

#import "XICOResolveUserCall.h"
#import "XICOResolveUserRestCall.h"
#import "XICOBlueprintUser.h"
#import <XivelySDK/XICommonError.h>
#import <XivelySDK/XIAuthenticationError.h>
#import <XivelySDK/XIEnvironment.h>
#import <XivelySDK/XISdkConfig+Selector.h>
#import "XICOBlueprintUser+AccessBlueprintUserType.h"


@interface XICOResolveUserRestCallTests : XCTestCase

@property(nonatomic, strong)XICOResolveUserRestCall *call;
@property(nonatomic, strong)OCMockObject *mockRestCallProvider;
@property(nonatomic, strong)OCMockObject *mockServicesConfig;
@property(nonatomic, strong)OCMockObject *mockDelegate;
@property(nonatomic, strong)OCMockObject *mockRestCall;

@property(nonatomic, strong)NSString *accountId;
@property(nonatomic, strong)NSString *accessUserId;


@end

@implementation XICOResolveUserRestCallTests

- (void)setUp {
    [super setUp];
    
    self.accountId = @"vbfsvfbngfnmdfgmhgjtgfngfngfd";
    self.accessUserId = @"sdlgksdfgfdslkgjhfsdklgfdshglkfdshglfkdsghfdslkghj";
    
    self.mockRestCallProvider = [OCMockObject mockForProtocol:@protocol(XIRESTCallProvider)];
    self.mockServicesConfig = [OCMockObject mockForClass:[XIServicesConfig class]];
    self.mockDelegate = [OCMockObject mockForProtocol:@protocol(XICOResolveUserCallDelegate)];
    self.mockRestCall = [OCMockObject mockForProtocol:@protocol(XIRESTCall)];
    
    self.call = [[XICOResolveUserRestCall alloc] initWithLogger:nil
                                                  restCallProvider:(id<XIRESTCallProvider>)self.mockRestCallProvider
                                                    servicesConfig:(XIServicesConfig *)self.mockServicesConfig];
    self.call.delegate = (id<XICOResolveUserCallDelegate>)self.mockDelegate;
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testXICOBlueprintUserEndUserCreation {
    NSString *userId = @"f053d818-7b0d-49ee-b5c5-71aab751a3af";
    NSString *accountId = @"5839bd5e-dd56-4483-be10-7e012e096ea7";
    NSString *organizationId = @"72ebdefe-3b11-496a-84c6-19905c8136a6";
    NSString *name = @"Ben Xively";
    
    NSDictionary *dict = @{@"accountId" : accountId,
                           @"address" : [NSNull null],
                           @"city" : [NSNull null],
                           @"countryCode" : [NSNull null],
                           @"created" : @"2015-07-30T13:35:24.000Z",
                           @"createdById" : [NSNull null],
                           @"emailAddress" : @"benxively@gmail.com",
                           @"endUserTemplateId" : @"1c127221-3d12-11e5-bd83-06e45ffd1689",
                           @"id" : @"2c2535ef-8d82-4e56-8df0-3022b95d3c5c",
                           @"lastModified" : @"2015-07-30T13:35:24.000Z",
                           @"lastModifiedById" : [NSNull null],
                           @"name" : name,
                           @"organizationId" : organizationId,
                           @"phoneNumber" : [NSNull null],
                           @"postalCode" : [NSNull null],
                           @"state" : [NSNull null],
                           @"userId" : userId,
                           @"version" : @"2Q"};
    
    XICOBlueprintUser *user = [[XICOBlueprintUser alloc] initWithUserType:XICOBlueprintUserTypeEndUser Dictionary:dict];
    XCTAssert(user, @"Creation failed");
    
    XCTAssertEqual(user.userType, XICOBlueprintUserTypeEndUser, @"userType mismatch");
    XCTAssert([user.accessUserId isEqualToString:userId], @"accessUserId mismatch");
    XCTAssert([user.accountId isEqualToString:accountId], @"accountId mismatch");
    XCTAssert([user.organizationId isEqualToString:organizationId], @"organizationId mismatch");
    XCTAssert([user.name isEqualToString:name], @"name mismatch");
}

- (void)testXICOBlueprintUserTypeToAccessVlueprintUserType {
    XICOBlueprintUser *blueprintUser = [[XICOBlueprintUser alloc] initWithUserType:XICOBlueprintUserTypeAccountUser Dictionary:@{}];
    XCTAssertEqual(blueprintUser.accessBlueprintUserType, XIAccessBlueprintUserTypeAccountUser, @"Account user converting failed");
    
    blueprintUser = [[XICOBlueprintUser alloc] initWithUserType:XICOBlueprintUserTypeEndUser Dictionary:@{}];
    XCTAssertEqual(blueprintUser.accessBlueprintUserType, XIAccessBlueprintUserTypeEndUser, @"End user converting failed");
    
    blueprintUser = [[XICOBlueprintUser alloc] initWithUserType:XICOBlueprintUserTypeUndefined Dictionary:@{}];
    XCTAssertEqual(blueprintUser.accessBlueprintUserType, XIAccessBlueprintUserTypeUndefined, @"Undefined user converting failed");

}

- (void)testXICOBlueprintUserAccountUserCreation {
    NSString *userId = @"f053d818-7b0d-49ee-b5c5-71aab751a3af";
    NSString *accountId = @"5839bd5e-dd56-4483-be10-7e012e096ea7";
    NSNull *organizationId = [NSNull null];
    NSString *name = @"Ben Xively";
    
    NSDictionary *dict = @{@"accountId" : accountId,
                           @"address" : [NSNull null],
                           @"city" : [NSNull null],
                           @"countryCode" : [NSNull null],
                           @"created" : @"2015-07-30T13:35:24.000Z",
                           @"createdById" : [NSNull null],
                           @"emailAddress" : @"benxively@gmail.com",
                           @"endUserTemplateId" : @"1c127221-3d12-11e5-bd83-06e45ffd1689",
                           @"id" : @"2c2535ef-8d82-4e56-8df0-3022b95d3c5c",
                           @"lastModified" : @"2015-07-30T13:35:24.000Z",
                           @"lastModifiedById" : [NSNull null],
                           @"name" : name,
                           @"organizationId" : organizationId,
                           @"phoneNumber" : [NSNull null],
                           @"postalCode" : [NSNull null],
                           @"state" : [NSNull null],
                           @"userId" : userId,
                           @"version" : @"2Q"};
    
    XICOBlueprintUser *user = [[XICOBlueprintUser alloc] initWithUserType:XICOBlueprintUserTypeAccountUser Dictionary:dict];
    XCTAssert(user, @"Creation failed");
    
    XCTAssertEqual(user.userType, XICOBlueprintUserTypeAccountUser, @"userType mismatch");
    XCTAssert([user.accessUserId isEqualToString:userId], @"accessUserId mismatch");
    XCTAssert([user.accountId isEqualToString:accountId], @"accountId mismatch");
    XCTAssertNil(user.organizationId, @"organizationId mismatch");
    XCTAssert([user.name isEqualToString:name], @"name mismatch");
}

- (void)testXICOResolveUserRestCallCreation {
    XCTAssert(self.call, @"Creation failed");
}

- (void)testXICOResolveUserRestCallStartRequest {
    NSString *endUsersPath = @"/api/v1/end-users";
    NSString *accountUsersPath = @"/api/v1/account-users";
    NSString *batchServiceUrl = @"https://blueprint.dev.xively.us/api/v1/batch";
    
    [[[self.mockServicesConfig expect] andReturn: endUsersPath] blueprintEndUsersEndpointPath];
    [[[self.mockServicesConfig expect] andReturn: accountUsersPath] blueprintAccountUsersEndpointPath];
    [[[self.mockServicesConfig expect] andReturn: batchServiceUrl] blueprintBatchServiceUrl];
    
    [[[self.mockRestCallProvider expect] andReturn:self.mockRestCall] getEmptyRESTCall];
    [[self.mockRestCall expect] setDelegate:(id<NSFileManagerDelegate>)self.call];
    
    XISdkConfig *sdkConfig = [XISdkConfig configWithHTTPResponseTimeout:1 urlSession:nil mqttConnectTimeout:1 mqttRetryAttempt:1 mqttWaitOnReconnect:1 environment:XIEnvironmentLive];
    [[[self.mockServicesConfig stub] andReturn:sdkConfig] sdkConfig];
    
    [[self.mockRestCall expect] startWithURL: batchServiceUrl
                                      method: XIRESTCallMethodPOST
                                     headers: [OCMArg any]
                                        body: [OCMArg checkWithBlock:^BOOL(id obj) {
        NSData *data = (NSData *)obj;
        NSError *error = nil;
        NSDictionary *rootDict = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&error];
        if (error) return NO;
        NSArray *requests = rootDict[@"requests"];
        NSString *accountIdQueryItem = [NSString stringWithFormat:@"accountId=%@", self.accountId];
        NSString *userIdQueryItem = [NSString stringWithFormat:@"userId=%@", self.accessUserId];
        
        
        NSDictionary *request = requests[0];
        if (! [request[@"method"] isEqualToString:@"get"]) return NO;
        NSString *path = request[@"path"];
        if ([path rangeOfString: endUsersPath].location == NSNotFound ||
              [path rangeOfString: accountIdQueryItem].location == NSNotFound ||
              [path rangeOfString: userIdQueryItem].location == NSNotFound) {
            return NO;
        }
        
        request = requests[1];
        if (! [request[@"method"] isEqualToString:@"get"]) return NO;
        path = request[@"path"];
        if ([path rangeOfString: accountUsersPath].location == NSNotFound ||
              [path rangeOfString: accountIdQueryItem].location == NSNotFound ||
              [path rangeOfString: userIdQueryItem].location == NSNotFound) {
            return NO;
        }
        
        
        return YES;
    }]];
    
    [self.call requestUserWithAccountId:self.accountId idmUserId:self.accessUserId];
    
    [self.mockServicesConfig verify];
    [self.mockRestCallProvider verify];
    [self.mockRestCall verify];
}

- (void)testXICOResolveUserRestCallCancelStartedRequest {
    [self testXICOResolveUserRestCallStartRequest];
    
    [[self.mockRestCall expect] cancel];
    [self.call cancel];
    [self.mockRestCall verify];
}

- (void)testXICOResolveUserRestCallErrorRestCallback {
    NSError *error = [NSError errorWithDomain:@"sfbg" code:38 userInfo:nil];
    
    [[self.mockDelegate expect] resolveUserCall:self.call didFailWithError:error];
    [self.call XIRESTCall:nil didFinishWithError:error];
    [self.mockDelegate verify];
}

- (void)testXICOResolveUserRestCallAccountUserReceived {
    
    NSArray *response = @[
        @{
      @"endUsers" : @{
              @"meta" : @{
                      @"count" : @0,
                      @"page" : @1,
                      @"pageSize" : @10,
                      @"sortOrder" : @"asc"
                      },
              @"results" : @[]
        },
    },
    @{
      @"accountUsers" : @{
              @"meta" : @{
                      @"count" : @1,
                      @"page" : @1,
                      @"pageSize" : @10,
                      @"sortOrder" : @"asc"
            },
              @"results" : @[
                               @{
                                   @"accountId" : @"5839bd5e-dd56-4483-be10-7e012e096ea7",
                                   @"accountUserTemplateId" : @"14d11daf-3d12-11e5-bd83-06e45ffd1689",
                                   @"created" : @"2015-10-22T09:11:40.000Z",
                                   @"createdById" : [NSNull null],
                                   @"id" : @"5ce907bd-088a-4449-aba0-9949407efc89",
                                   @"lastModified" : @"2015-10-22T09:11:40.000Z",
                                   @"lastModifiedById" : [NSNull null],
                                   @"name" : @"au003",
                                   @"userId" : @"47ca75ca-03d0-4b7b-891a-7715a4984343",
                                   @"version" : @"M2"
                               },
                               @{
                                   @"accountId" : @"5839bd5e-dd56-448",
                                   @"accountUserTemplateId" : @"14d11daf-3d12-11e5-bd83-06e45ffd1689",
                                   @"created" : @"2015-10-22T09:11:40.000Z",
                                   @"createdById" : [NSNull null],
                                   @"id" : @"5ce907bd-088a-4449-aba0-9949407efc89",
                                   @"lastModified" : @"2015-10-22T09:11:40.000Z",
                                   @"lastModifiedById" : [NSNull null],
                                   @"name" : @"au003",
                                   @"userId" : @"47ca75ca-03d0-4b",
                                   @"version" : @"M2"
                                   }
                               ]
        }
    }
    ];
    NSError *error = nil;
    NSData *d = [NSJSONSerialization dataWithJSONObject:response options:0 error:&error];
    
    [[self.mockDelegate expect] resolveUserCall:self.call didReceiveUser:[OCMArg checkWithBlock:^BOOL(id obj) {
        XICOBlueprintUser *user = (XICOBlueprintUser *)obj;
        
        return [user.accountId isEqualToString:@"5839bd5e-dd56-4483-be10-7e012e096ea7"] &&
                [user.userId isEqualToString:@"5ce907bd-088a-4449-aba0-9949407efc89"] &&
        user.userType == XICOBlueprintUserTypeAccountUser;
    }]];
    [self.call XIRESTCall:nil didFinishWithData:d httpStatusCode:200];
    [self.mockDelegate verify];
}

- (void)testXICOResolveUserRestCallNOUserReceived {
    
    NSArray *response = @[
                          @{
                              @"endUsers" : @{
                                      @"meta" : @{
                                              @"count" : @0,
                                              @"page" : @1,
                                              @"pageSize" : @10,
                                              @"sortOrder" : @"asc"
                                              },
                                      @"results" : @[]
                                      },
                              },
                          @{
                              @"accountUsers" : @{
                                      @"meta" : @{
                                              @"count" : @1,
                                              @"page" : @1,
                                              @"pageSize" : @10,
                                              @"sortOrder" : @"asc"
                                              },
                                      @"results" : @[]
                                      }
                              }
                          ];
    NSError *error = nil;
    NSData *d = [NSJSONSerialization dataWithJSONObject:response options:0 error:&error];
    
    [[self.mockDelegate expect] resolveUserCall:self.call didFailWithError:[OCMArg checkWithBlock:^BOOL(id obj) {
        NSError *error = (NSError *)obj;
        return error.code == XIErrorInternal;
    }]];
    [self.call XIRESTCall:nil didFinishWithData:d httpStatusCode:200];
    [self.mockDelegate verify];
}

- (void)testXICOResolveUserRestCallEndUserReceived {
    
    NSArray *response = @[
                          @{
                              @"endUsers" : @{
                                      @"meta" : @{
                                              @"count" : @1,
                                              @"page" : @1,
                                              @"pageSize" : @10,
                                              @"sortOrder" : @"asc"
                                  },
                                      @"results" : @[
                                                     @{
                                                         @"accountId" : @"5839bd5e-dd56-4483-be10-7e012e096ea7",
                                                         @"address" : [NSNull null],
                                                         @"city" : [NSNull null],
                                                         @"countryCode" : [NSNull null],
                                                         @"created" : @"2015-07-30T13:35:24.000Z",
                                                         @"createdById" : [NSNull null],
                                                         @"emailAddress" : @"benxively@gmail.com",
                                                         @"endUserTemplateId" : @"1c127221-3d12-11e5-bd83-06e45ffd1689",
                                                         @"id" : @"2c2535ef-8d82-4e56-8df0-3022b95d3c5c",
                                                         @"lastModified" : @"2015-07-30T13:35:24.000Z",
                                                         @"lastModifiedById" : [NSNull null],
                                                         @"name" : @"Ben Xively",
                                                         @"organizationId" : @"72ebdefe-3b11-496a-84c6-19905c8136a6",
                                                         @"phoneNumber" : [NSNull null],
                                                         @"postalCode" : [NSNull null],
                                                         @"state" : [NSNull null],
                                                         @"userId" : @"f053d818-7b0d-49ee-b5c5-71aab751a3af",
                                                         @"version" : @"2Q"
                                                     },
                                                     @{
                                                         @"accountId" : @"5839bd5e-dd56-4483-be10-",
                                                         @"address" : [NSNull null],
                                                         @"city" : [NSNull null],
                                                         @"countryCode" : [NSNull null],
                                                         @"created" : @"2015-07-30T13:35:24.000Z",
                                                         @"createdById" : [NSNull null],
                                                         @"emailAddress" : @"benxively@gmail.com",
                                                         @"endUserTemplateId" : @"1c127221-3d12-11e5-bd83-06e45ffd1689",
                                                         @"id" : @"2c2535ef-8d82-4e56-8df0-3022b9",
                                                         @"lastModified" : @"2015-07-30T13:35:24.000Z",
                                                         @"lastModifiedById" : [NSNull null],
                                                         @"name" : @"Ben Xively",
                                                         @"organizationId" : @"72ebdefe-3b11-496a-84c6-19905c8136a6",
                                                         @"phoneNumber" : [NSNull null],
                                                         @"postalCode" : [NSNull null],
                                                         @"state" : [NSNull null],
                                                         @"userId" : @"f053d818-7b0d-49ee-b5c5-71aab751a3af",
                                                         @"version" : @"2Q"
                                                         }
                                                     ]
                              }
                              },
                          @{
                              @"error" : @{
                                      @"details" : @{
                                              @"code" : @21,
                                              @"message" : @"You are not allowed to view this entity or perform this action",
                                              @"target" : @"No target"
                                              }
                              }
                              }
                          ];
    NSError *error = nil;
    NSData *d = [NSJSONSerialization dataWithJSONObject:response options:0 error:&error];
    
    [[self.mockDelegate expect] resolveUserCall:self.call didReceiveUser:[OCMArg checkWithBlock:^BOOL(id obj) {
        XICOBlueprintUser *user = (XICOBlueprintUser *)obj;
        
        return [user.accountId isEqualToString:@"5839bd5e-dd56-4483-be10-7e012e096ea7"] &&
        [user.userId isEqualToString:@"2c2535ef-8d82-4e56-8df0-3022b95d3c5c"] &&
        user.userType == XICOBlueprintUserTypeEndUser;
    }]];
    [self.call XIRESTCall:nil didFinishWithData:d httpStatusCode:200];
    [self.mockDelegate verify];
}


- (void)testXICOGetEndUserRestCallChunkedJwtRetreival {
    NSArray *response = @[
                          @{
                              @"endUsers" : @{
                                      @"meta" : @{
                                              @"count" : @0,
                                              @"page" : @1,
                                              @"pageSize" : @10,
                                              @"sortOrder" : @"asc"
                                              },
                                      @"results" : @[]
                                      },
                              },
                          @{
                              @"accountUsers" : @{
                                      @"meta" : @{
                                              @"count" : @1,
                                              @"page" : @1,
                                              @"pageSize" : @10,
                                              @"sortOrder" : @"asc"
                                              },
                                      @"results" : @[
                                              @{
                                                  @"accountId" : @"5839bd5e-dd56-4483-be10-7e012e096ea7",
                                                  @"accountUserTemplateId" : @"14d11daf-3d12-11e5-bd83-06e45ffd1689",
                                                  @"created" : @"2015-10-22T09:11:40.000Z",
                                                  @"createdById" : [NSNull null],
                                                  @"id" : @"5ce907bd-088a-4449-aba0-9949407efc89",
                                                  @"lastModified" : @"2015-10-22T09:11:40.000Z",
                                                  @"lastModifiedById" : [NSNull null],
                                                  @"name" : @"au003",
                                                  @"userId" : @"47ca75ca-03d0-4b7b-891a-7715a4984343",
                                                  @"version" : @"M2"
                                                  },
                                              @{
                                                  @"accountId" : @"5839bd5e-dd56-44",
                                                  @"accountUserTemplateId" : @"14d11daf-3d12-11e5-bd83-06e45ffd1689",
                                                  @"created" : @"2015-10-22T09:11:40.000Z",
                                                  @"createdById" : [NSNull null],
                                                  @"id" : @"5ce907bd-088a-44",
                                                  @"lastModified" : @"2015-10-22T09:11:40.000Z",
                                                  @"lastModifiedById" : [NSNull null],
                                                  @"name" : @"au003",
                                                  @"userId" : @"47ca75ca-03d0-4b7b-891a-7715a4984343",
                                                  @"version" : @"M2"
                                                  }
                                              ]
                                      }
                              }
                          ];
    NSError *error = nil;
    NSData *d = [NSJSONSerialization dataWithJSONObject:response options:0 error:&error];
    d = [d subdataWithRange:NSMakeRange(0, 22)];
    
    [[self.mockDelegate expect] resolveUserCall:self.call didFailWithError:[OCMArg checkWithBlock:^BOOL(id obj) {
        NSError *error2 = (NSError *)obj;
        return error2.code == XIErrorInternal;
    }]];
    [self.call XIRESTCall:nil didFinishWithData:d httpStatusCode:200];
    [self.mockDelegate verify];
}

- (void)testXICOGetEndUserRestCallAnyOtherStatus {
    [[self.mockDelegate expect] resolveUserCall:self.call didFailWithError:[OCMArg checkWithBlock:^BOOL(id obj) {
        NSError *error2 = (NSError *)obj;
        return error2.code == XIErrorInternal;
    }]];
    [self.call XIRESTCall:nil didFinishWithData:nil httpStatusCode:99];
    [self.mockDelegate verify];
}


@end
