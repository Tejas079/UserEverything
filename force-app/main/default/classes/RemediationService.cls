public with sharing class RemediationService {
    private static final Map<String,Schema.SObjectType> PERMISSION_TYPES = new Map<String,Schema.SObjectType>{
        'PermissionSet' => PermissionSetAssignment.SObjectType,
        'SystemPermission' => PermissionSet.SObjectType
    };

    @AuraEnabled(cacheable=false)
    public static void revokePermission(String userId, String permissionType) {
        validatePermissionType(permissionType);
        
        if(permissionType == 'PermissionSet') {
            removePermissionSets(userId);
        } else if(permissionType == 'SystemPermission') {
            removeSystemPermissions(userId);
        }
    }

    @AuraEnabled(cacheable=false)
    public static void removeRole(String userId) {
        if(!Schema.SObjectType.User.fields.UserRoleId.isAccessible()) {
            throw new RemediationException('Insufficient access to User Role field');
        }

        List<User> users = [SELECT UserRoleId FROM User WHERE Id = :userId WITH USER_MODE LIMIT 1];
        if(!users.isEmpty() && users[0].UserRoleId != null) {
            users[0].UserRoleId = null;
            update Security.stripInaccessible(
                AccessType.UPDATABLE, 
                users,
                true
            ).getRecords();
        }
    }

    @AuraEnabled(cacheable=false)
    public static void revokePermissionSets(String userId) {
        System.debug('Revoking permission sets for: ' + userId);
        try {
            removePermissionSets(userId);
            System.debug('Successfully revoked permissions');
        } catch(Exception e) {
            System.debug('Error in revokePermissionSets: ' + e.getMessage());
            throw new AuraHandledException('Revocation failed: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false) 
    public static void resetSystemPermissions(String userId) {
        removeSystemPermissions(userId);
    }

    private static void removePermissionSets(String userId) {
        List<PermissionSetAssignment> assignments = [
            SELECT Id FROM PermissionSetAssignment 
            WHERE AssigneeId = :userId 
            AND PermissionSet.IsOwnedByProfile = false
            WITH USER_MODE
        ];
        
        if(!assignments.isEmpty()) {
            delete Security.stripInaccessible(
                AccessType.UPDATABLE, 
                assignments,
                true
            ).getRecords();
        }
    }

    private static void removeSystemPermissions(String userId) {
        if(UserInfo.getUserId() == userId) {
            throw new RemediationException('Cannot reset permissions for current user');
        }

        User u = [SELECT Id, ProfileId FROM User WHERE Id = :userId WITH USER_MODE];
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' WITH USER_MODE];
        
        if(u.ProfileId != p.Id) {
            u.ProfileId = p.Id;
            
            try {
                update Security.stripInaccessible(
                    AccessType.UPDATABLE,
                    new List<User>{u},
                    true
                ).getRecords();
            } catch(DmlException e) {
                throw new RemediationException(
                    'Profile update failed: ' + e.getMessage() + 
                    ' - Users cannot modify their own profile'
                );
            }
        }
    }

    private static void validatePermissionType(String type) {
        if(!PERMISSION_TYPES.containsKey(type)) {
            throw new RemediationException('Invalid permission type: ' + type);
        }
        if(!PERMISSION_TYPES.get(type).getDescribe().isDeletable()) {
            throw new RemediationException('Insufficient permissions to delete ' + type);
        }
    }

    public class RemediationException extends Exception {}
}