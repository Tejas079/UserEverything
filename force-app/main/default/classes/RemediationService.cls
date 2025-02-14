public with sharing class RemediationService {
    private static final Map<String,Schema.SObjectType> PERMISSION_TYPES = new Map<String,Schema.SObjectType>{
        'PermissionSet' => PermissionSetAssignment.SObjectType,
        'SystemPermission' => PermissionSet.SObjectType
    };

    private static final Map<Id, List<PermissionSetAssignment>> undoPermissionSets = new Map<Id, List<PermissionSetAssignment>>();
    private static final Map<Id, Id> originalProfiles = new Map<Id, Id>();

    private static final String UNDO_TYPE_PERMISSIONS = 'PermissionSet';
    private static final String UNDO_TYPE_PROFILE = 'Profile';

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
        List<PermissionSetAssignment> assignments = [
            SELECT Id, AssigneeId, PermissionSetId 
            FROM PermissionSetAssignment 
            WHERE AssigneeId = :userId 
            AND PermissionSet.IsOwnedByProfile = false
            WITH USER_MODE
        ];
        
        if(!assignments.isEmpty()) {
            // Save undo state first
            saveUndoState(userId, UNDO_TYPE_PERMISSIONS, JSON.serialize(assignments));
            
            // Process setup object in separate transaction
            deletePermissionSetAssignments(JSON.serialize(assignments));
        }
    }

    @future
    private static void deletePermissionSetAssignments(String assignmentsJSON) {
        List<PermissionSetAssignment> assignments = 
            (List<PermissionSetAssignment>)JSON.deserialize(
                assignmentsJSON, 
                List<PermissionSetAssignment>.class
            );
        
        delete Security.stripInaccessible(
            AccessType.UPDATABLE, 
            assignments,
            true
        ).getRecords();
    }

    @AuraEnabled(cacheable=false) 
    public static void resetSystemPermissions(String userId) {
        removeSystemPermissions(userId);
    }

    private static void removePermissionSets(String userId) {
        List<PermissionSetAssignment> assignments = [
            SELECT Id, AssigneeId, PermissionSetId 
            FROM PermissionSetAssignment 
            WHERE AssigneeId = :userId 
            AND PermissionSet.IsOwnedByProfile = false
            WITH USER_MODE
        ];
        
        if(!assignments.isEmpty()) {
            undoPermissionSets.put(userId, assignments.deepClone(true));
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
        originalProfiles.put(userId, u.ProfileId);
        
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' WITH USER_MODE];
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

    @AuraEnabled(cacheable=false)
    public static void undoRevokePermissionSets(String userId) {
        try {
            List<PermissionSetUndoo__c> undoRecords = [
                SELECT Id, Data__c 
                FROM PermissionSetUndoo__c 
                WHERE UserId__c = :userId 
                AND Type__c = :UNDO_TYPE_PERMISSIONS
                AND IsProcessed__c = false
                WITH USER_MODE
            ];
            
            if(undoRecords.isEmpty()) {
                throw new RemediationException('No undo records found');
            }

            List<PermissionSetAssignment> assignments = (List<PermissionSetAssignment>)
                JSON.deserializeStrict(undoRecords[0].Data__c, List<PermissionSetAssignment>.class);
            
            // Clear IDs and process in separate transaction
            processUndoAssignments(JSON.serialize(assignments), undoRecords[0].Id);
            
        } catch(Exception e) {
            throw new RemediationException('Undo failed: ' + e.getMessage());
        }
    }

    @future 
    private static void processUndoAssignments(String assignmentsJSON, String undoRecordId) {
        // Process setup object first
        List<PermissionSetAssignment> assignments = 
            (List<PermissionSetAssignment>)JSON.deserialize(
                assignmentsJSON, 
                List<PermissionSetAssignment>.class
            );
        
        for(PermissionSetAssignment psa : assignments) {
            psa.Id = null;
        }
        
        insert Security.stripInaccessible(
            AccessType.CREATABLE,
            assignments,
            true
        ).getRecords();

        // Enqueue custom object deletion in queueable
        System.enqueueJob(new UndoRecordCleanupQueueable(undoRecordId));
    }

    @AuraEnabled(cacheable=false)
    public static void undoResetSystemPermissions(String userId) {
        if(originalProfiles.containsKey(userId)) {
            User u = new User(Id = userId, ProfileId = originalProfiles.get(userId));
            update Security.stripInaccessible(
                AccessType.UPDATABLE,
                new List<User>{u},
                true
            ).getRecords();
            originalProfiles.remove(userId);
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

    private static void saveUndoState(String userId, String type, String data) {
        PermissionSetUndoo__c undoRecord = new PermissionSetUndoo__c(
            UserId__c = userId,
            Type__c = type,
            Data__c = data,
            IsProcessed__c = false
        );
        
        insert Security.stripInaccessible(
            AccessType.CREATABLE, 
            new List<PermissionSetUndoo__c>{undoRecord},
            true
        ).getRecords();
    }

    public class RemediationException extends Exception {}

    public class UndoRecordCleanupQueueable implements Queueable {
        private String undoRecordId;
        
        public UndoRecordCleanupQueueable(String undoRecordId) {
            this.undoRecordId = undoRecordId;
        }
        
        public void execute(QueueableContext context) {
            delete [SELECT Id FROM PermissionSetUndoo__c WHERE Id = :this.undoRecordId];
        }
    }
}