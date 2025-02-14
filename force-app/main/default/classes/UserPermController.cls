/**
* @File Name : UserPermController.cls
* @Description :
* @Author : Tejas kshirsagar
* @Last Modified By :
* @Last Modified On : February 4, 2025
* @Modification Log :
*==============================================================================
* Ver | Date | Author | Modification
*==============================================================================
* 1.0 | February 4, 2025 |   | Initial Version
* Features like showing the Recordtype , object permissions, field permissions

**/

public with sharing class UserPermController {
    
    // Define the UserPermissionAccess class
    public class UserPermissionAccess {
        public List<String> systemPermissions;
        public List<ObjectPermissions> objectPermissions;
    }
    
    // Fetch permissions for the selected user
    @AuraEnabled(cacheable=true)
    public static List<User> getActiveUsers() {
        List<User> activeUsers = [SELECT Id, Name FROM User where IsActive = true ORDER BY Name
                                 ];
        return activeUsers;
    }
    
    @AuraEnabled
    public static Map<String, Object> getUserPermissions(String userId) {
        Map<String, Object> result = new Map<String, Object>();
        
        User u = [SELECT Id, IsActive, Profile.Name, Profile.Id 
                  FROM User 
                  WHERE Id = :userId];
        
        Set<Id> permissionSetIds = new Set<Id>{u.Profile.Id};
            
            // Rest of your existing logic
            List<PermissionSetAssignment> assignments = [
                SELECT PermissionSet.Id, PermissionSet.Name 
                FROM PermissionSetAssignment 
                WHERE AssigneeId = :userId
            ];
        
        for(PermissionSetAssignment psa : assignments) {
            permissionSetIds.add(psa.PermissionSet.Id);
        }
        
        result.put('profileName', u.Profile.Name);
        result.put('permissionSetNames', new List<String>());
        
        for(PermissionSet ps : [
            SELECT Name 
            FROM PermissionSet 
            WHERE Id IN :permissionSetIds
        ]) {
            ((List<String>)result.get('permissionSetNames')).add(ps.Name);
        }
        
        return result;
    }
    
    /*  @AuraEnabled
public static Map<String, Object> getObjectPermissions(String userId, Integer page, Integer pageSize) {
Map<String, Object> result = new Map<String, Object>();
User u = [SELECT Profile.Id FROM User WHERE Id = :userId];
Set<Id> permissionSetIds = new Set<Id>{u.Profile.Id};

List<PermissionSetAssignment> permissionSets = [
SELECT PermissionSetId 
FROM PermissionSetAssignment 
WHERE AssigneeId = :userId
];
for (PermissionSetAssignment psa : permissionSets) {
permissionSetIds.add(psa.PermissionSetId);
}

Integer offset = (page - 1) * pageSize;

result.put('total', [SELECT COUNT() FROM ObjectPermissions WHERE ParentId IN :permissionSetIds]);
result.put('data', [
SELECT SObjectType, PermissionsRead, PermissionsCreate, 
PermissionsEdit, PermissionsDelete 
FROM ObjectPermissions 
WHERE ParentId IN :permissionSetIds
ORDER BY SObjectType
LIMIT :pageSize
OFFSET :offset
]);

return result;
}*/
   @AuraEnabled(cacheable=true)
    public static Map<String, Object> getObjectPermissions(String userId, Integer page, Integer pageSize, String searchTerm) {
        Map<String, Object> result = new Map<String, Object>();
        Set<Id> permissionSetIds = getPermissionSetIds(userId);
        
        // Get matching objects first if search term exists
        Set<String> objectNames = new Set<String>();
        if(String.isNotBlank(searchTerm)) {
            String searchPattern = '%' + String.escapeSingleQuotes(searchTerm) + '%';
            List<EntityDefinition> objects = [
                SELECT QualifiedApiName 
                FROM EntityDefinition 
                WHERE QualifiedApiName LIKE :searchPattern
            ];
            for(EntityDefinition obj : objects) {
                objectNames.add(obj.QualifiedApiName);
            }
        }

        String query = 'SELECT SobjectType, PermissionsRead, PermissionsCreate, ' +
                      'PermissionsEdit, PermissionsDelete ' +
                      'FROM ObjectPermissions ' +
                      'WHERE ParentId IN :permissionSetIds ';
        
        if(!objectNames.isEmpty()) {
            query += 'AND SobjectType IN :objectNames ';
        }
        
        query += 'ORDER BY SobjectType ' +
                'LIMIT :pageSize ' +
                'OFFSET :offset';

        Integer offset = (page - 1) * pageSize;
        
        try {
            result.put('data', Database.queryWithBinds(
                query,
                new Map<String, Object>{
                    'permissionSetIds' => permissionSetIds,
                    'objectNames' => objectNames,
                    'pageSize' => pageSize,
                    'offset' => offset
                },
                AccessLevel.USER_MODE
            ));
            
            // Count query
            String countQuery = 'SELECT COUNT() FROM ObjectPermissions WHERE ParentId IN :permissionSetIds ';
            if(!objectNames.isEmpty()) {
                countQuery += 'AND SobjectType IN :objectNames';
            }
            
            result.put('total', Database.countQueryWithBinds(
                countQuery,
                new Map<String, Object>{
                    'permissionSetIds' => permissionSetIds,
                    'objectNames' => objectNames
                },
                AccessLevel.USER_MODE
            ));
            
        } catch(Exception e) {
            result.put('data', new List<Object>());
            result.put('total', 0);
        }
        
        return result;
    }
    
    
    
    
    /*
   

* it was giving offset 2000 limit issue
   *   @AuraEnabled
    public static Map<String, Object> getFieldPermissions(String userId, Integer page, Integer pageSize) {
        Map<String, Object> result = new Map<String, Object>();
        User u = [SELECT Profile.Id FROM User WHERE Id = :userId];
        Set<Id> permissionSetIds = new Set<Id>{u.Profile.Id};
            
            List<PermissionSetAssignment> permissionSets = [
                SELECT PermissionSetId 
                FROM PermissionSetAssignment 
                WHERE AssigneeId = :userId
            ];
        for (PermissionSetAssignment psa : permissionSets) {
            permissionSetIds.add(psa.PermissionSetId);
        }
        
        Integer offset = (page - 1) * pageSize;
        
        result.put('total', [SELECT COUNT() FROM FieldPermissions WHERE ParentId IN :permissionSetIds]);
        result.put('data', [
            SELECT SObjectType, Field, PermissionsRead, PermissionsEdit 
            FROM FieldPermissions 
            WHERE ParentId IN :permissionSetIds
            ORDER BY SObjectType, Field
            LIMIT :pageSize
            OFFSET :offset
        ]);
        
        return result;
    }
    */
    @AuraEnabled
    public static Map<String, Object> getFieldPermissions(String userId, String lastRecordId, String searchTerm) {
        Set<Id> permissionSetIds = getPermissionSetIds(userId);
        Map<String, Object> result = new Map<String, Object>();
        
        // Query for matching objects and fields
        Set<String> objectNames = new Set<String>();
        Set<String> fieldNames = new Set<String>();
        
        if(String.isNotBlank(searchTerm)) {
            String searchPattern = '%' + String.escapeSingleQuotes(searchTerm) + '%';
            
            // First get matching objects
            List<EntityDefinition> objects = [
                SELECT Id, QualifiedApiName 
                FROM EntityDefinition 
                WHERE QualifiedApiName LIKE :searchPattern
            ];
            
            Set<Id> objectIds = new Set<Id>();
            for(EntityDefinition obj : objects) {
                objectNames.add(obj.QualifiedApiName);
                objectIds.add(obj.Id);
            }
            
            // Then find fields in those objects
            if(!objectIds.isEmpty()) {
                List<FieldDefinition> fields = [
                    SELECT QualifiedApiName 
                    FROM FieldDefinition 
                    WHERE EntityDefinitionId IN :objectIds
                    AND QualifiedApiName LIKE :searchPattern
                ];
                for(FieldDefinition fld : fields) {
                    fieldNames.add(fld.QualifiedApiName);
                }
            }
        }
        
        String query = 'SELECT SobjectType, Field, PermissionsRead, PermissionsEdit ' +
            'FROM FieldPermissions ' +
            'WHERE ParentId IN :permissionSetIds ' +
            (String.isNotBlank(searchTerm) 
             ? ' AND (SobjectType IN :objectNames OR Field IN :fieldNames) ' 
             : '') +
            (String.isNotBlank(lastRecordId) ? ' AND Id > :lastRecordId ' : '') +
            'ORDER BY Id, SobjectType, Field ' +
            'LIMIT 100';
        
        List<FieldPermissions> perms = Database.query(query);
        
        // Deduplicate results using a map
        Map<String, FieldPermissions> uniquePerms = new Map<String, FieldPermissions>();
        for(FieldPermissions fp : perms) {
            String key = fp.SobjectType + '|' + fp.Field;
            if(!uniquePerms.containsKey(key)) {
                uniquePerms.put(key, fp);
            } else {
                // Merge permissions if duplicate exists
                FieldPermissions existing = uniquePerms.get(key);
                existing.PermissionsRead = existing.PermissionsRead || fp.PermissionsRead;
                existing.PermissionsEdit = existing.PermissionsEdit || fp.PermissionsEdit;
            }
        }
        
        result.put('data', uniquePerms.values());
        result.put('lastRecordId', perms.isEmpty() ? null : perms[perms.size()-1].Id);
        
        return result;
    } 
    
    // Reusable permission set method 
    /* private static Set<Id> getPermissionSetIds(String userId) {
    Set<Id> permissionSetIds = new Set<Id>();
    
    try {
        // Get user's profile
        User u = [SELECT Profile.Name FROM User WHERE Id = :userId];
        
        // Get Profile's associated PermissionSet
       List<PermissionSet> profilePermissionSets = [
    SELECT Id 
    FROM PermissionSet 
    WHERE ProfileId = :u.Profile.Id 
    AND Type = 'Profile'
    LIMIT 1
];
        
        if(!profilePermissionSets.isEmpty()) {
            permissionSetIds.add(profilePermissionSets[0].Id);
        }

        // Get assigned permission sets
        List<PermissionSetAssignment> assignments = [
            SELECT PermissionSetId 
            FROM PermissionSetAssignment 
            WHERE AssigneeId = :userId
        ];
        
        for(PermissionSetAssignment psa : assignments) {
            if(psa.PermissionSetId != null) {
                permissionSetIds.add(psa.PermissionSetId);
            }
        }
        
    } catch(Exception e) {
        throw new AuraHandledException('Error getting permission sets: ' + e.getMessage());
    }
    
    System.debug('Permission Set IDs: ' + permissionSetIds);
    return permissionSetIds;
} */
    private static Set<Id> getPermissionSetIds(String userId) {
    Set<Id> permissionSetIds = new Set<Id>();
    
    try {
        User u = [SELECT ProfileId FROM User WHERE Id = :userId];
        
        // Get Profile's associated PermissionSet
        List<PermissionSet> profilePermissionSets = [
            SELECT Id 
            FROM PermissionSet 
            WHERE ProfileId = :u.ProfileId 
            AND Type = 'Profile'
            LIMIT 1
        ];
        
        if(!profilePermissionSets.isEmpty()) {
            permissionSetIds.add(profilePermissionSets[0].Id);
        }

        // Get assigned permission sets
        List<PermissionSetAssignment> assignments = [
            SELECT PermissionSetId 
            FROM PermissionSetAssignment 
            WHERE AssigneeId = :userId
        ];
        
        for(PermissionSetAssignment psa : assignments) {
            permissionSetIds.add(psa.PermissionSetId);
        }
        
    } catch(Exception e) {
        throw new AuraHandledException('Error getting permission sets: ' + e.getMessage());
    }
    
    return permissionSetIds;
}

   public class RecordTypeWrapper {
    @AuraEnabled public String objectName;
    @AuraEnabled public String profileName;
    @AuraEnabled public String recordTypeName;
    @AuraEnabled public String assignedVia; // Add this field
    
    public RecordTypeWrapper(String obj, String profile, String rt, String via) {
        objectName = obj;
        profileName = profile;
        recordTypeName = rt;
        assignedVia = via; // Initialize new field
    }
}
    
  /*private static String getSessionIdFromVisualForce() {
        return Page.sessionidpage.getContent().toString().trim();
    }*/
    
   /*AuraEnabled(cacheable=true)
    public static List<RecordTypeWrapper> getRecordTypeAssignments(Id userId) {
        system.debug('userId-'+userId);
        
        User userRecord = [SELECT Profile.Name FROM User WHERE Id = :userId];
        list<String> profileName = new list<String>();
        profileName.add(userRecord.Profile.Name);
        
        List<RecordTypeWrapper> results = new List<RecordTypeWrapper>();
        Map<String, String> profileMap = new Map<String, String>{
            'System Administrator' => 'Admin',
                'Standard User' => 'Standard',
                'Standard Platform User' => 'StandardAul',
                'High Volume Customer Portal' => 'HighVolumePortal',
                'Solution Manager' => 'SolutionManager',
                'Marketing User' => 'MarketingProfile',
                'Contract Manager' => 'ContractManager',
                'Chatter Free User' => 'Chatter Free User',
                'Analytics Cloud Integration User' => 'Analytics Cloud Integration User',
                'Analytics Cloud Security User' => 'Analytics Cloud Security User',
                'Customer Community Login User' => 'Customer Community Login User',
                'Cross Org Data Proxy User' => 'Cross Org Data Proxy User',
                'Work.com Only User' => 'Work.com Only User',
                'Identity User' => 'Identity User',
                'Customer Community Plus User' => 'Customer Community Plus User',
                'Silver Partner User' => 'Silver Partner User',
                'Gold Partner User' => 'Gold Partner User',
                'Customer Portal Manager' => 'Customer Portal Manager Standard',
                'Force.com - App Subscription User' => 'Force.com - App Subscription User',
                'Customer Community Plus Login User' => 'Customer Community Plus Login User',
                'Partner App Subscription User' => 'Partner App Subscription User',
                'External Identity User' => 'External Identity User',
                'Partner Community Login User' => 'Partner Community Login User',
                'Customer Community User' => 'Customer Community User',
                'Force.com - Free User' => 'Force.com - Free User',
                'Chatter Moderator User' => 'Chatter Moderator User',
                'Chatter External User' => 'Chatter External User',
                'High Volume Customer Portal User' => 'High Volume Customer Portal User',
                'Read Only' => 'Read Only',
                'Service Cloud' => 'ServiceCloud',
                'Partner User' => 'Partner'
                };
                    
                    List<String> translatedProfiles = new List<String>();
        for (String pp : profileName) {
            if (profileMap.containsKey(pp)) {
                translatedProfiles.add(profileMap.get(pp));
            } else {
                translatedProfiles.add(pp); // Add original name if no mapping found
            }
        }
        
        
        
        try {
            MetadataService.MetadataPort service = new MetadataService.MetadataPort();
            service.SessionHeader = new MetadataService.SessionHeader_element();
           service.SessionHeader.sessionId = getSessionIdFromVisualForce(); // Updated line
           //  service.SessionHeader.sessionId = UserInfo.getSessionId();
            // Read Profile metadata directly
            List<MetadataService.Metadata> mdList = service.readMetadata(
                'Profile',
                translatedProfiles
            ).getRecords();
            System.debug('Profile names received: ' + translatedProfiles);
            System.debug('Number of metadata records: ' + mdList.size());
            
            for (MetadataService.Metadata md : mdList) {
                // CORRECTED: Check for Profile type instead of ReadProfileResult
                if (md instanceof MetadataService.Profile) {
                    MetadataService.Profile profile = (MetadataService.Profile) md;
                    System.debug('Processing profile: ' + profile.fullName);
                    System.debug('RecordTypeVisibilities exists? ' + (profile.recordTypeVisibilities != null));
                    
                    if (profile.recordTypeVisibilities != null) {
                        for (MetadataService.ProfileRecordTypeVisibility rtVis : profile.recordTypeVisibilities) {
                            System.debug('RecordType: ' + rtVis.recordType + ', Visible: ' + rtVis.visible);
                            if (rtVis.visible) {
                                String[] parts = rtVis.recordType.split('\\.');
                                results.add(new RecordTypeWrapper(
                                    parts[0],         // Object name
                                    profile.fullName, // Profile name
                                    parts.size() > 1 ? parts[1] : '', // Record Type name
                                    'Profile'         // Hardcoded source since we're querying profiles
                                ));
                            }
                        }
                    }
                }
            }
        } catch(Exception e) {
            throw new AuraHandledException('Error retrieving record types: ' + e.getMessage());
        }
        System.debug('Record Type Results: ' + JSON.serializePretty(results));
        return results;
    }
    */
    
    // Add to UserPermController.cls
     
@AuraEnabled(cacheable=true)
public static Map<String, Boolean> getSystemLevelPermissions(String userId) {
    Map<String, Boolean> permissions = new Map<String, Boolean>{
        'View_All_Data' => false,
        'Modify_All_Data' => false,
        'Manage_Users' => false,
        'Author_Apex' => false,
        'Customize_Application' => false,
        'View_Setup' => false
    };
    
    try {
        List<User> users = [SELECT ProfileId FROM User WHERE Id = :userId LIMIT 1];
        if(users.isEmpty()) return permissions;
        User u = users[0];
       
        Set<Id> permissionSetIds = new Set<Id>{u.ProfileId};
        
        for(PermissionSetAssignment psa : [
            SELECT PermissionSetId 
            FROM PermissionSetAssignment 
            WHERE AssigneeId = :userId
        ]) {
            if(psa.PermissionSetId != null) {
                permissionSetIds.add(psa.PermissionSetId);
            }
        }
         System.debug('permissionSetIds--'+permissionSetIds);
        for(PermissionSet ps : [
            SELECT PermissionsViewAllData, PermissionsModifyAllData,
                   PermissionsManageUsers, PermissionsAuthorApex,
                   PermissionsCustomizeApplication, PermissionsViewSetup
            FROM PermissionSet 
            WHERE Id IN :permissionSetIds
        ]) {
            if(ps != null) {
                permissions.put('View_All_Data', permissions.get('View_All_Data') || ps.PermissionsViewAllData);
                permissions.put('Modify_All_Data', permissions.get('Modify_All_Data') || ps.PermissionsModifyAllData);
                permissions.put('Manage_Users', permissions.get('Manage_Users') || ps.PermissionsManageUsers);
                permissions.put('Author_Apex', permissions.get('Author_Apex') || ps.PermissionsAuthorApex);
                permissions.put('Customize_Application', permissions.get('Customize_Application') || ps.PermissionsCustomizeApplication);
                permissions.put('View_Setup', permissions.get('View_Setup') || ps.PermissionsViewSetup);
            }
        }
        
    } catch(Exception e) {
        System.debug('Error: ' + e.getMessage());
    }
      System.debug('permissions==='+permissions);
    return permissions;
}    

// Add new Apex methods
@AuraEnabled(cacheable=true)
public static List<SharingRuleWrapper> getSharingRulesAccess(String userId) {
    List<SharingRuleWrapper> results = new List<SharingRuleWrapper>();
    
    // Get sharing rules for the user's role and groups
    for(GroupMember gm : [
        SELECT Group.DeveloperName, Group.Type, UserOrGroupId 
        FROM GroupMember 
        WHERE UserOrGroupId = :userId
    ]) {
        results.add(new SharingRuleWrapper(
            'Group',
            gm.Group.DeveloperName,
            'Read/Write',
            gm.Group.Type
        ));
    }
    
    // Add other sharing rule types as needed
    return results;
}

@AuraEnabled(cacheable=true)
public static List<RoleHierarchyWrapper> getRoleHierarchy(String userId) {
    List<RoleHierarchyWrapper> hierarchy = new List<RoleHierarchyWrapper>();
    
    User u = [SELECT UserRoleId FROM User WHERE Id = :userId];
    if(u.UserRoleId == null) return hierarchy;
    
    Map<Id, UserRole> roles = new Map<Id, UserRole>([
        SELECT Id, Name, ParentRoleId 
        FROM UserRole
    ]);
    
    // Build hierarchy tree
    Set<Id> processedIds = new Set<Id>();
    Id currentRoleId = u.UserRoleId;
    
    while(currentRoleId != null && !processedIds.contains(currentRoleId)) {
        UserRole role = roles.get(currentRoleId);
        hierarchy.add(new RoleHierarchyWrapper(
            role.Name,
            roles.containsKey(role.ParentRoleId) ? roles.get(role.ParentRoleId).Name : '',
            'Inherited'
        ));
        processedIds.add(currentRoleId);
        currentRoleId = role.ParentRoleId;
    }
    
    return hierarchy;
}

// Wrapper classes
public class SharingRuleWrapper {
    @AuraEnabled public String objectName;
    @AuraEnabled public String sharingType;
    @AuraEnabled public String accessLevel;
    @AuraEnabled public String sharedWith;
    
    public SharingRuleWrapper(String obj, String type, String access, String with) {
        objectName = obj;
        sharingType = type;
        accessLevel = access;
        sharedWith = with;
    }
}

public class RoleHierarchyWrapper {
    @AuraEnabled public String roleName;
    @AuraEnabled public String parentRole;
    @AuraEnabled public String accessLevel;
    @AuraEnabled public String id;
    
    public RoleHierarchyWrapper(String name, String parent, String access) {
        roleName = name;
        parentRole = parent;
        accessLevel = access;
        id = EncodingUtil.convertToHex(Crypto.generateDigest('MD5', Blob.valueOf(name + parent)));
    }
}

@AuraEnabled(cacheable=true)
public static AccessRiskAnalyzer.RiskResult getAccessRiskScore(Id userId) {
    return AccessRiskAnalyzer.analyzeUserRisk(userId);
}

// Add this method for risk analysis
public static UserPermissionAccess getUserPermissionAccess(Id userId) {
    UserPermissionAccess perms = new UserPermissionAccess();
    perms.systemPermissions = new List<String>();
    perms.objectPermissions = new List<ObjectPermissions>();

    // Get profile and permission sets
    Set<Id> permissionSetIds = new Set<Id>();
    
    // Get user's profile
    User u = [SELECT ProfileId FROM User WHERE Id = :userId];
    permissionSetIds.add(u.ProfileId);
    
    // Get assigned permission sets
    for(PermissionSetAssignment psa : [
        SELECT PermissionSetId 
        FROM PermissionSetAssignment 
        WHERE AssigneeId = :userId
    ]) {
        permissionSetIds.add(psa.PermissionSetId);
    }
    
    // Get system permissions
    for(PermissionSet ps : [
        SELECT PermissionsModifyAllData, PermissionsManageUsers, 
               PermissionsApiEnabled 
        FROM PermissionSet 
        WHERE Id IN :permissionSetIds
    ]) {
        if(ps.PermissionsModifyAllData) perms.systemPermissions.add('ModifyAllData');
        if(ps.PermissionsManageUsers) perms.systemPermissions.add('ManageUsers');
        if(ps.PermissionsApiEnabled) perms.systemPermissions.add('ApiEnabled');
    }
    
    // Get object permissions
    perms.objectPermissions = [
        SELECT SobjectType 
        FROM ObjectPermissions 
        WHERE ParentId IN :permissionSetIds
    ];
    
    return perms;
}
 
public class UserDetailsWrapper {
    @AuraEnabled public String userName;
    @AuraEnabled public String userEmail;
    @AuraEnabled public String profileName;
    @AuraEnabled public Boolean isActive;
    @AuraEnabled public List<String> permissionSets;
    @AuraEnabled public Integer riskScore;
    @AuraEnabled public String riskLevel;
    @AuraEnabled public Integer highRiskCount;
}

@AuraEnabled(cacheable=true)
public static UserDetailsWrapper getUserDetails(Id userId) {
    // Query user details
    User u = [SELECT Name, Email, Profile.Name, IsActive 
              FROM User 
              WHERE Id = :userId 
              LIMIT 1];
    if (u == null) {
        throw new AuraHandledException('User not found');
    }

    // Analyze risk
    AccessRiskAnalyzer.RiskResult riskResult = AccessRiskAnalyzer.analyzeUserRisk(userId);

    // Create and populate wrapper
    UserDetailsWrapper wrapper = new UserDetailsWrapper();
    wrapper.userName = u.Name;
    wrapper.userEmail = u.Email;
    wrapper.profileName = u.Profile.Name;
    wrapper.isActive = u.IsActive;
    wrapper.permissionSets = getPermissionSets(userId);
    wrapper.riskScore = riskResult.riskScore;
    wrapper.riskLevel = riskResult.riskLevel;
    wrapper.highRiskCount = riskResult.highRiskCount;

    return wrapper;
}

private static List<String> getPermissionSets(Id userId) {
    // Query PermissionSetAssignments for the given user
    List<PermissionSetAssignment> assignments = [
        SELECT PermissionSet.Name 
        FROM PermissionSetAssignment 
        WHERE AssigneeId = :userId
    ];

    // Create a list to store permission set names
    List<String> permissionSetNames = new List<String>();

    // Iterate through the query results and add names to the list
    for (PermissionSetAssignment psa : assignments) {
        permissionSetNames.add(psa.PermissionSet.Name);
    }

    // Return the list of permission set names
    return permissionSetNames;
}
}