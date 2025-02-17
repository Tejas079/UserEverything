import { LightningElement, wire, track } from 'lwc';
import getActiveUsers from '@salesforce/apex/UserPermController.getActiveUsers';
import getUserPermissions from '@salesforce/apex/UserPermController.getUserPermissions';
import getObjectPermissions from '@salesforce/apex/UserPermController.getObjectPermissions';
import getFieldPermissions from '@salesforce/apex/UserPermController.getFieldPermissions';
//import getRecordTypeAssignments from '@salesforce/apex/UserPermController.getRecordTypeAssignments';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSystemLevelPermissions from '@salesforce/apex/UserPermController.getSystemLevelPermissions';
import getSharingRulesAccess from '@salesforce/apex/UserPermController.getSharingRulesAccess';
import getRoleHierarchy from '@salesforce/apex/UserPermController.getRoleHierarchy';
import getUserDetails from '@salesforce/apex/UserPermController.getUserDetails';
import analyzeUserRisk from '@salesforce/apex/AccessRiskAnalyzer.analyzeUserRisk';
import revokePermissionSets from '@salesforce/apex/RemediationService.revokePermissionSets';
import resetSystemPermissions from '@salesforce/apex/RemediationService.resetSystemPermissions';
import undoRevokePermissionSets from '@salesforce/apex/RemediationService.undoRevokePermissionSets';
import undoResetSystemPermissions from '@salesforce/apex/RemediationService.undoResetSystemPermissions';
 


// Add these cleaning functions at the top
const cleanFieldName = (field) => {
    //console.log('Original field:', field);
    const parts = field.split('.');
    const cleaned = parts.length > 1 ? parts.pop() : field;
    //console.log('Cleaned field:', cleaned);
    return cleaned;
};

const cleanObjectName = (object) => {
    return object.replace(/SA_Audit__/g, '').replace(/__c/g, '');
};

export default class CloneUserManager extends LightningElement {
    // User Details Section
    @track userDetails = {
        userName: '',
        userEmail: '',
        profileName: '',
        isActive: false,
        permissionSets: [],
        highRiskCount: 0,
        riskScore: 0,
        riskLevel: 'Low',
        criticalFindings: []
    };

    // User Selection
    @track userOptions = [];
    @track selectedUserId;

    // Component Initialization
    connectedCallback() {
        this.loadActiveUsers();
    }
    resetAllData() {
        this.userDetails = {
            userName: '',
            userEmail: '',
            profileName: '',
            isActive: false,
            permissionSets: [],
            highRiskCount: 0,
            riskScore: 0,
            riskLevel: 'Low',
            criticalFindings: []
        };
        
        this.objectPermissions = [];
        this.fieldPermissions = [];
        this.systemPermissions = [];
        this.recordTypePermissions = [];
        this.sharingRules = [];
        this.roleHierarchy = [];
        
        // Reset pagination
        this.currentObjectPage = 1;
        this.currentFieldPage = 1;
        
        // Clear any error states
        this.error = undefined;
    }


    // Load active users for combobox
    async loadActiveUsers() {
        try {
            const users = await getActiveUsers();
            this.userOptions = users.map(user => ({
                label: user.Name,
                value: user.Id
            }));
        } catch(error) {
            this.showErrorToast('User Load Error', error.body.message);
        }
    }

    // Main user change handler
    async handleUserChange(event) {
        this.currentObjectPage = 1;
        this.currentFieldPage = 1;
        try {
            this.selectedUserId = event.detail.value;
            this.isInitialLoading = true;
            
            // Clear previous data immediately
            this.resetAllData();
            
            // Sequential loading for dependent data
            await this.loadUserDetails();
            
            // Parallel loading for independent data
            await Promise.all([
                this.loadRiskAnalysis(),
                this.loadObjectPermissions(),
                this.loadFieldPermissions(),
                this.loadSystemPermissions()
            ]);
            
        } catch(error) {
            this.showErrorToast('Load Failed', 
                error.body?.message ||  // Use optional chaining
                error.message || 
                'Failed to load user data'
            );
            this.resetAllData();
        } finally {
            this.isInitialLoading = false;
        }
    }

    // User Details Implementation
    async loadUserDetails() {
        try {
            console.log('Loading user details for:', this.selectedUserId);
            const data = await getUserDetails({ userId: this.selectedUserId });
            console.log('Raw user details response:', JSON.stringify(data));
            
            this.userDetails = Object.assign(
                {}, 
                this.userDetails, 
                {
                    userName: data.userName,
                    userEmail: data.userEmail,
                    profileName: data.profileName,
                    isActive: data.isActive,
                    permissionSets: data.permissionSets || []
                }
            );
            
            console.log('Processed userDetails:', JSON.stringify({
                ...this.userDetails,
                permissionSets: this.userDetails.permissionSets.length
            }));
        } catch(error) {
            console.error('User details error:', JSON.stringify(error));
            this.showErrorToast('User Details Error', 
                error.body?.message || error.message
            );
        }
    }

    // Risk Analysis Implementation
    async loadRiskAnalysis() {
        try {
            console.log('Loading risk analysis for:', this.selectedUserId);
            const riskResult = await analyzeUserRisk({ userId: this.selectedUserId });
            console.log('Raw risk analysis:', JSON.parse(JSON.stringify(riskResult)));
            
            this.userDetails = Object.assign(
                {},
                this.userDetails,
                {
                    highRiskCount: riskResult.highRiskCount,
                    riskScore: riskResult.riskScore,
                    riskLevel: riskResult.riskLevel,
                    criticalFindings: riskResult.criticalFindings
                }
            );
            
            console.log('Updated userDetails with risk:', JSON.parse(JSON.stringify(this.userDetails)));
        } catch(error) {
            console.error('Risk analysis error:', error);
            this.showErrorToast('Risk Analysis Error', error.body.message);
        }
    }

    // Getters for derived properties
    get userIsActive() {
        return this.userDetails.isActive ? 'Active' : 'Inactive';
    }

    get userStatusVariant() {
        return this.userDetails.isActive ? 'success' : 'error';
    }

    get totalPermissions() {
        return (this.userDetails.permissionSets?.length || 0) + 
               (this.systemPermissions?.length || 0);
    }

    // Toast utility
    showErrorToast(title, message) {
        const safeMessage = message || 'Unknown error occurred';
        
        // Handle specific error messages
        if(safeMessage.includes('Cannot reset permissions for current user')) {
            safeMessage = 'You cannot reset permissions for your own user account';
        }
        
        this.dispatchEvent(new ShowToastEvent({
            title: title || 'Error',
            message: safeMessage,
            variant: 'error',
            mode: 'sticky'
        }));
    }
    

    @track showSystemPermissions = false;
    systemPermissions = [];
    objectPermissions = [];
    fieldPermissions;
    itemsPerPage = 100;
    currentObjectPage = 1;
    currentFieldPage = 1;
    totalObjectRecords = 0;
    totalFieldRecords = 0;
    showObjects = false;
    showFields = false;
    showRecordTypes = false;
    @track recordTypePermissions = [];
    recordTypeColumns = [
        { label: 'Object', fieldName: 'objectName' },
        { label: 'Record Type', fieldName: 'recordTypeName' },
        { label: 'Profile', fieldName: 'profileName' },
        { label: 'Assigned Via', fieldName: 'assignedVia' }
    ];
    systemPermissionColumns = [
        { label: 'Permission', fieldName: 'permission', type: 'text' },
        { label: 'Status', fieldName: 'status', type: 'text' }
    ];

    // Define table columns
    objectColumns = [
        { 
            label: 'Object', 
            //fieldName: 'SobjectType', 
            fieldName: 'objectName',
            type: 'text',
            cellAttributes: { class: 'slds-text-title_bold' } 
        },
        { 
            label: 'Read', 
            fieldName: 'PermissionsRead', 
            type: 'boolean',
            cellAttributes: { 
                iconName: { fieldName: 'readIcon' },
                iconLabel: { fieldName: 'readLabel' }
            }
        },
        { 
            label: 'Create', 
            fieldName: 'PermissionsCreate', 
            type: 'boolean',
            cellAttributes: { 
                iconName: { fieldName: 'createIcon' },
                iconLabel: { fieldName: 'createLabel' }
            }
        },
        { 
            label: 'Edit', 
            fieldName: 'PermissionsEdit', 
            type: 'boolean',
            cellAttributes: { 
                iconName: { fieldName: 'editIcon' },
                iconLabel: { fieldName: 'editLabel' }
            }
        },
        { 
            label: 'Delete', 
            fieldName: 'PermissionsDelete', 
            type: 'boolean',
            cellAttributes: { 
                iconName: { fieldName: 'deleteIcon' },
                iconLabel: { fieldName: 'deleteLabel' }
            }
        },
        { 
            label: 'AssignedBy', 
            fieldName: 'assignedBy', 
            type: 'text',
             
            sortable: true
        },
        { 
            label: 'AssignmentMethod', 
            fieldName: 'assignmentMethod', 
            type: 'text',
             
            sortable: true
        },
         
        { 
            label: 'Source Type', 
            fieldName: 'sourceType', 
            type: 'text',
            cellAttributes: {
                class: 'source-type-badge {sourceBadgeClass}'
            },
            sortable: true
        },
        { 
            label: 'Source Name', 
            fieldName: 'sourceName', 
            type: 'text',
            sortable: true
        }
    ];

    // Modified field columns definition
    fieldColumns = [
        { 
            label: 'Object', 
            fieldName: 'object',
            type: 'text', // Changed from text to button type
             
            cellAttributes: { 
                class: 'slds-text-title_bold ',
                style: 'background-color: #e3e0ff; color: #181818;'
            },
            iconName: 'utility:standard_objects', // Add object type icon
            iconPosition: 'left',
            sortable: true,
            initialWidth: 250
        },
        { 
            label: 'Field', 
            fieldName: 'field',   // Matches cleaned data
            type: 'text',
            cellAttributes: { class: 'slds-truncate ' } 
        },
        { 
            label: 'Read', 
            fieldName: 'PermissionsRead', 
            type: 'boolean',
            cellAttributes: {
                iconName: { fieldName: 'readIcon' },
                iconLabel: { fieldName: 'readLabel' }
            }
        },
        { 
            label: 'Edit', 
            fieldName: 'PermissionsEdit', 
            type: 'boolean',
            cellAttributes: {
                iconName: { fieldName: 'editIcon' },
                iconLabel: { fieldName: 'editLabel' }
            }
        }
    ];

    // Add to class properties
    searchTerm = '';
    fieldSearchTerm = '';

    // Modified field permissions handling
    fieldLastRecordId = null;
    fieldPageData = [];

    // Add search mode tracking
    searchMode = false;

    // Add to component properties
    currentObjectPage = 1;
    itemsPerObjectPage = 50;
    totalObjectRecords = 0;
    objectSearchTimeout;

    // Add to class properties
   // _showSystemPermissions = false;

    // Track all merged records
    allMergedObjects = new Map();

    // Add to component properties
    @track showSharingRules = false;
    @track showRoleHierarchy = false;
    @track sharingRules = [];
    @track roleHierarchy = [];

    // Add column definitions
    sharingRuleColumns = [
        { label: 'Object', fieldName: 'objectName', type: 'text' },
        { label: 'Sharing Type', fieldName: 'sharingType', type: 'text' },
        { label: 'Access Level', fieldName: 'accessLevel', type: 'text' },
        { label: 'Shared With', fieldName: 'sharedWith', type: 'text' }
    ];

    roleHierarchyColumns = [
        { label: 'Role Name', fieldName: 'roleName', type: 'text' },
        { label: 'Parent Role', fieldName: 'parentRole', type: 'text' },
        { label: 'Access Level', fieldName: 'accessLevel', type: 'text' }
    ];

    // Load users on component load
    @wire(getActiveUsers)
    wiredUsers({ data, error }) {
        if (data) {
            this.userOptions = data.map(user => ({
                label: user.Name,
                value: user.Id
            }));
        }
    }
    handleClearSearch() {
        this.searchTerm = '';
        this.currentObjectPage = 1;
        this.loadObjectPermissions();
    }
    

    

    async loadObjectPermissions() {
        try {
            const { data, total } = await getObjectPermissions({
                userId: this.selectedUserId,
                page: this.currentObjectPage,
                pageSize: this.itemsPerPage,
                searchTerm: this.searchTerm,
            });

            // REPLACE existing records instead of merging
            if(this.currentObjectPage === 1) {
                this.allMergedObjects.clear();
            }

            // Store unique records but don't slice for pagination
            data.forEach(op => {
                const key = op.SobjectType;
                this.allMergedObjects.set(key, op);
            });

            // Always use server-side total for pagination
            // this.totalObjectRecords = total;
            
            // Show only current page results
         // this.objectPermissions = data;
         this.objectPermissions = data.map(perm => ({
            objectName: perm.objectName,  // Explicit mapping
            PermissionsRead: perm.canRead,
            PermissionsCreate: perm.canCreate,
            PermissionsEdit: perm.canEdit,
            PermissionsDelete: perm.canDelete,
            sourceType: perm.sourceType,
            assignedBy: perm.assignedBy,
            assignmentMethod : perm.assignmentMethod,
            sourceName: perm.sourceName,
            sourceBadgeClass: this.getSourceBadgeClass(perm.sourceType)
        }));
        this.totalObjectRecords = total;
        this.error = undefined;
            
    } catch(error) {
        this.objectPermissions = [];
        this.totalObjectRecords = 0;
        this.showErrorToast('Load Error', error.body?.message || error.message);
    } finally {
        this.isLoading = false;
    }
    }
    getSourceBadgeClass(sourceType) {
        const styleMap = {
            'Profile': 'slds-theme_success',
            'Permission Set': 'slds-theme_warning',
            'Package': 'slds-theme_alt-inverse'
        };
        return `slds-badge badge-small ${styleMap[sourceType] || ''}`;
    }

    async loadFieldPermissions() {
        try {
            //this.isLoading = true;
            const result = await getFieldPermissions({
                userId: this.selectedUserId,
                lastRecordId: this.fieldLastRecordId,
                searchTerm: this.fieldSearchTerm || null
            });

            // Process and merge in one step
            this.fieldPageData = [
                ...this.fieldPageData, 
                ...this.mergeFieldPermissions(result.data)
            ];
            
            this.fieldLastRecordId = result.lastRecordId;
            this.fieldPermissions = [...this.fieldPageData];
            
        } catch(error) {
            console.error(error);
        } finally {
            //this.isLoading = false;
        }
    }

    toggleObjects() {
        this.showObjects = !this.showObjects;
        if (this.showObjects) {
            this.currentObjectPage = 1;
            this.loadObjectPermissions();
        }
    }

    toggleFields() {
        this.showFields = !this.showFields;
        if (this.showFields) {
            this.currentFieldPage = 1;
            this.loadFieldPermissions();
        }
    }
    get hasData() {
        return this.paginatedFieldPermissions?.length > 0;
    }

    toggleRecordTypes() {
        this.showRecordTypes = !this.showRecordTypes;
        if(this.showRecordTypes) {
           // this.loadUserPermissions();
        }
    }

    toggleSystemPermissions() {
        this.showSystemPermissions = !this.showSystemPermissions
        if(this.showSystemPermissions ) {
            this.loadSystemPermissions();
        }
    }

    handleSharingRulesToggle() {
        this.showSharingRules = ! this.showSharingRules;
        if(this.showSharingRules && this.selectedUserId) {
            this.loadSharingRules();
        }
    }

    handleRoleHierarchyToggle() {
        this.showRoleHierarchy = !this.showRoleHierarchy ;
        if(this.showRoleHierarchy && this.selectedUserId) {
            this.loadRoleHierarchy();
        }
    }

    handleObjectPrevious() {
        if(this.currentObjectPage > 1) {
            this.currentObjectPage--;
            this.loadObjectPermissions();
        }
    }

    handleObjectNext() {
        if(!this.disableObjectNextButton) {
            this.currentObjectPage++;
            this.loadObjectPermissions();
        }
    }

    handleFieldPrevious() {
        if(this.currentFieldPage > 1) {
            this.currentFieldPage--;
        }
    }

    async handleFieldNext() {
        if(this.hasMoreFields) {
            this.currentFieldPage++;
            // Only load more if we don't have enough client-side data
            if(this.currentFieldPage * this.itemsPerPage > this.fieldPageData.length) {
                await this.loadFieldPermissions();
            }
        }
    }

    get objectPageInfo() {
        return this.getPageInfo(this.currentObjectPage, this.totalObjectRecords);
    }

    get fieldPageInfo() {
        return this.getPageInfo(this.currentFieldPage, this.totalFieldRecords);
    }

    getPageInfo(currentPage, totalRecords) {
        const validTotal = totalRecords || 0;
        const start = ((currentPage - 1) * this.itemsPerPage) + 1;
        const end = Math.min(currentPage * this.itemsPerPage, validTotal);
        return validTotal > 0 ? `Showing ${start}-${end} of ${validTotal} records` : 'No records found';
    }

    get objectIcon() {
        return this.showObjects ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get fieldIcon() {
        return this.showFields ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get isFirstObjectPage() {
        return this.currentObjectPage === 1;
    }

    get isLastObjectPage() {
        return this.currentObjectPage * this.itemsPerPage >= this.totalObjectRecords;
    }

    get isFirstFieldPage() {
        return this.currentFieldPage === 1;
    }

    get isLastFieldPage() {
        // Check both client-side data and server-side availability
        return !this.hasMoreFields && 
               this.currentFieldPage * this.itemsPerPage >= this.fieldPageData.length;
    }

    

    get recordTypeIcon() {
        return this.showRecordTypes ? 'utility:chevronup' : 'utility:chevrondown';
    }

    /*async loadUserPermissions() {
        try {
            const result = await getRecordTypeAssignments({ 
                userId: this.selectedUserId 
            }) || [];
            
            this.recordTypePermissions = result.map(rt => ({
                objectName: rt.objectName || '',
                recordTypeName: rt.recordTypeName || '',
                profileName: rt.profileName || '',
                assignedVia: rt.assignedVia || ''
            }));
            
        } catch(error) {
            this.recordTypePermissions = [];
        }
    }*/

    // Replace the toggle methods with these
    handleRecordTypeToggle(event) {
        this.showRecordTypes = event.detail.checked;
    }

    handleObjectToggle(event) {
        this.showObjects = event.detail.checked;
        if(this.showObjects && this.objectPermissions.length === 0) {
            this.loadObjectPermissions();
        }
    }

    handleFieldToggle(event) {
        this.showFields = event.detail.checked;
    }

    handleSystemPermissionsToggle(event) {
        this.showSystemPermissions = event.detail.checked;
        if(this.showSystemPermissions && !this.systemPermissions.length) {
            this.loadSystemPermissions();
        }
    }

    // Corrected handler method
    /*async handleObjectSearch(event) {
        this.searchTerm = event.detail.value;
        this.currentObjectPage = 1;
        await this.loadObjectPermissions();
    }*/
        async handleObjectSearch(event) {
            // Get search term from event properly
            const searchTerm = event.detail.value; // For lightning-input use event.detail.value
            // const searchTerm = event.target.value; // For standard HTML input
            
            // Add null check and proper reference
            if (searchTerm && searchTerm.length < 3) {
                this.showToast('Info', 'Please enter at least 3 characters to search', 'info');
                return;
            }
            
            // Assign to class property
            this.searchTerm = searchTerm;
            this.currentObjectPage = 1;
            await this.loadObjectPermissions();
        }


    // Modified filtered getter with proper reactivity
    /*get filteredObjectPermissions() {
        return this.objectPermissions;
    }*/
        get filteredObjectPermissions() {
            return this.objectPermissions.filter(perm => 
                perm.objectName.toLowerCase().includes(this.searchTerm?.toLowerCase() || '')
            );
        }
    // Modified search handler
    async handleFieldSearch(event) {
        this.fieldSearchTerm = event.detail.value.trim();
        this.currentFieldPage = 1;
        this.fieldPageData = []; // Reset accumulated data
        this.fieldLastRecordId = null;
        await this.loadFieldPermissions();
    }

    // Update filtered field permissions getter
    get filteredFieldPermissions() {
        if (!this.fieldPageData) return [];
        if (!this.fieldSearchTerm) return this.fieldPageData;
        
        const searchTerm = this.fieldSearchTerm.toLowerCase();
        return this.fieldPageData.filter(fp => {
            const objectMatch = fp.object?.toLowerCase().includes(searchTerm);
            const fieldMatch = fp.field?.toLowerCase().includes(searchTerm);
            return objectMatch || fieldMatch;
        });
    }

    // Update paginated getter to use filtered results
    get paginatedFieldPermissions() {
        const start = (this.currentFieldPage - 1) * this.itemsPerPage;
        return this.fieldPageData.slice(start, start + this.itemsPerPage);
    }

    // Update total records getter
    get totalFieldRecords() {
        return this.fieldPageData.length;
    }

    get hasMoreFields() {
        // Only consider server-side more records when we have a last ID
        return this.fieldLastRecordId !== null;
    }

    get disableNextButton() {
        // Enable if we have more fields OR client-side data allows next page
        return !this.hasMoreFields && 
               this.currentFieldPage * this.itemsPerPage >= this.fieldPageData.length;
    }

    get disablePreviousButton() {
        return this.isFirstFieldPage;
    }

    get pageInfo() {
        const total = this.fieldPageData.length;
        const start = Math.min((this.currentFieldPage - 1) * this.itemsPerPage + 1, total);
        const end = Math.min(start + this.itemsPerPage - 1, total);
        return total > 0 ? `Showing ${start}-${end} of ${total}` : 'No results';
    }

    get filteredCount() {
        return this.filteredFieldPermissions.length;
    }

    // Client-side deduplication
    mergeFieldPermissions(data) {
        const merged = new Map();
        
        data.forEach(fp => {
            const key = `${fp.SobjectType}_${fp.Field}`;
            if(!merged.has(key)) {
                merged.set(key, {
                    ...fp,
                    object: cleanObjectName(fp.SobjectType),
                    field: cleanFieldName(fp.Field),
                    key: key,
                    PermissionsRead: false,
                    PermissionsEdit: false
                });
            }
            
            const existing = merged.get(key);
            merged.set(key, {
                ...existing,
                PermissionsRead: existing.PermissionsRead || fp.PermissionsRead,
                PermissionsEdit: existing.PermissionsEdit || fp.PermissionsEdit
            });
        });
        
        return Array.from(merged.values());
    }

    async loadSystemPermissions() {
        try {
            const perms = await getSystemLevelPermissions({ 
                userId: this.selectedUserId 
            });
            this.systemPermissions = Object.entries(perms).map(([key, value]) => ({
                permission: key.replace(/_/g, ' '),
                status: value ? 'Enabled' : 'Disabled'
            }));
        } catch(error) {
            this.systemPermissions = [];
        }
    }

    get systemPermissionsCount() {
        return this.systemPermissions?.length || 0;
    }

    async connectedCallback() {
        await this.loadSystemPermissions();
        // Test cleanFieldName directly
        console.log('TEST cleanFieldName:', cleanFieldName('Contact.OtherPhone')); // Should log "OtherPhone"
        console.log('TEST cleanFieldName:', cleanFieldName('Account.Name')); // Should log "Name"
    }

    activeSection = {
        fields: true,
        system: false
    };

    handleSectionToggle(event) {
        const section = event.currentTarget.dataset.section;
        this.activeSection = {
            ...this.activeSection,
            [section]: !this.activeSection[section]
        };
        
        // Lazy load data when section activated
        if(this.activeSection[section] && !this[`${section}DataLoaded`]) {
            this[`load${section.charAt(0).toUpperCase() + section.slice(1)}Permissions`]();
            this[`${section}DataLoaded`] = true;
        }
    }

    get disableObjectNextButton() {
        return this.currentObjectPage * this.itemsPerPage >= this.totalObjectRecords;
    }

    // Update getter
    get showSystemPermissions() {
        return this._showSystemPermissions;
    }

    // Object Permissions Table
    get objectTableClasses() {
        return `slds-table slds-table_cell-buffer slds-table_bordered ${this.showObjects ? '' : 'slds-hidden'}`;
    }

    // Field Permissions Table (existing)
    get fieldTableClasses() {
        return `slds-table slds-table_cell-buffer slds-table_bordered ${this.showFields ? '' : 'slds-hidden'}`;
    }

    // Add this method to handle object permission merging
    mergeObjectPermissions(newData) {
        const merged = new Map();
        
        newData.forEach(op => {
            const objectName = op.SobjectType || 'Unknown Object';
            const key = objectName;
            
            if(merged.has(key)) {
                const existing = merged.get(key);
                existing.PermissionsRead = existing.PermissionsRead || op.PermissionsRead;
                existing.PermissionsCreate = existing.PermissionsCreate || op.PermissionsCreate;
                existing.PermissionsEdit = existing.PermissionsEdit || op.PermissionsEdit;
                existing.PermissionsDelete = existing.PermissionsDelete || op.PermissionsDelete;
            } else {
                merged.set(key, {
                    ...op,
                    SobjectType: objectName,
                    PermissionsRead: Boolean(op.PermissionsRead),
                    readIcon: op.PermissionsRead ? 'action:check' : 'action:close',
                    readLabel: op.PermissionsRead ? 'Allowed' : 'Denied',
                    PermissionsCreate: Boolean(op.PermissionsCreate),
                    createIcon: op.PermissionsCreate ? 'action:check' : 'action:close',
                    createLabel: op.PermissionsCreate ? 'Allowed' : 'Denied',
                    PermissionsEdit: Boolean(op.PermissionsEdit),
                    editIcon: op.PermissionsEdit ? 'action:check' : 'action:close',
                    editLabel: op.PermissionsEdit ? 'Allowed' : 'Denied',
                    PermissionsDelete: Boolean(op.PermissionsDelete),
                    deleteIcon: op.PermissionsDelete ? 'action:check' : 'action:close',
                    deleteLabel: op.PermissionsDelete ? 'Allowed' : 'Denied'
                });
            }
            console.log('Merged object:', { 
                key, 
                read: Boolean(op.PermissionsRead),
                create: Boolean(op.PermissionsCreate)
            });
        });
        
        return Array.from(merged.values());
    }

    // Add toggle handlers
   

    // Add data loading methods
    async loadSharingRules() {
        try {
            this.sharingRules = await getSharingRulesAccess({ userId: this.selectedUserId });
        } catch(error) {
            this.sharingRules = [];
            this.showToast('Error', error.body.message, 'error');
        }
    }

    async loadRoleHierarchy() {
        try {
            this.roleHierarchy = await getRoleHierarchy({ userId: this.selectedUserId });
        } catch(error) {
            this.roleHierarchy = [];
            this.showToast('Error', error.body.message, 'error');
        }
    }

    // Add getters for counts
    get sharingRulesCount() {
        return this.sharingRules?.length || 0;
    }

    get roleHierarchyCount() {
        return this.roleHierarchy?.length || 0;
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }

    @track toggleStates = {
        recordtypes: false,
        objects: false,
        fields: false,
        systempermissions: false,
        sharingrules: false,
        rolehierarchy: false
    };

    handleToggleChange(event) {
        const toggleId = event.target.id;
        const isChecked = event.target.checked;
        
        // Update the corresponding property based on toggle ID
        switch(toggleId) {
            case 'recordTypesToggle':
                this.showRecordTypes = isChecked;
                break;
            case 'objectsToggle':
                this.showObjects = isChecked;
                break;
            case 'fieldsToggle':
                this.showFields = isChecked;
                break;
            case 'systemPermissionsToggle':
                this.showSystemPermissions = isChecked;
                break;
            case 'sharingRulesToggle':
                this.showSharingRules = isChecked;
                break;
            case 'roleHierarchyToggle':
                this.showRoleHierarchy = isChecked;
                break;
        }
        
        console.log('Toggle state changed:', toggleId, isChecked);
    }

    get showRecordTypes() { return this.toggleStates.recordtypes; }
    get showObjects() { return this.toggleStates.objects; }
    get showFields() { return this.toggleStates.fields; }
    get showSystemPermissions() { return this.toggleStates.systempermissions; }
    get showSharingRules() { return this.toggleStates.sharingrules; }
    get showRoleHierarchy() { return this.toggleStates.rolehierarchy; }

    showInfoMessage() {
        const infoMessage = 'Select the toggles below to view and manage different permission types';
        this.dispatchEvent(new ShowToastEvent({
            title: 'Information',
            message: infoMessage,
            variant: 'info'
        }));
    }

    // Add getters for derived properties
    get userIsActive() {
        return this.userDetails.isActive ? 'Active' : 'Inactive';
    }

    get userStatusVariant() {
        return this.userDetails.isActive ? 'success' : 'error';
    }

    get riskLevelVariant() {
        return (this.userDetails.riskLevel || '').toLowerCase();
    }

    // Add these getters
    get statusIcon() {
        return this.userDetails.isActive ? 'utility:success' : 'utility:error';
    }

    get statusLabel() {
        return this.userDetails.isActive ? 'Active' : 'Inactive';
    }

    get statusVariant() {
        return this.statusLabel === 'Active' ? 'success' : 'error';
    }

    // Add to class properties
    remediationActions = [
        { label: 'Revoke Permission Sets', value: 'revokePermissionSets' },
        { label: 'Reset System Permissions', value: 'resetSystemPermissions' }
    ];
    selectedAction = 'revokePermissionSets';

    // Add after existing methods
    handleActionChange(event) {
        this.selectedAction = event.detail.value;
    }

    // Add to class properties
    showUndoButton = false;
    lastActionType = null;

    // Modify executeRemediation
    async executeRemediation() {
        this.isLoading = true;
        this.isInitialLoading = false;
        try {
            // Add null checks for critical parameters
            if(!this.selectedUserId || !this.selectedAction) {
                throw new Error('Missing required parameters for remediation');
            }

            // Explicit method calls instead of dynamic dispatch
            if(this.selectedAction === 'revokePermissionSets') {
                await revokePermissionSets({ userId: this.selectedUserId });
            } else if(this.selectedAction === 'resetSystemPermissions') {
                await resetSystemPermissions({ userId: this.selectedUserId });
            } else {
                throw new Error('Invalid remediation action selected');
            }
            this.isLoading = false;
            this.showUndoButton = true;
            this.lastActionType = this.selectedAction;
            // Refresh data with error handling
           /* await Promise.allSettled([
                this.loadUserDetails(),
                this.loadSystemPermissions()
            ]);*/
            await this.refreshData();
            this.showToast('Success', 'Remediation completed successfully', 'success');
            this.isInitialLoading = false;
        } catch(error) {
            this.isLoading = false;
            console.error('Remediation error:', error);
            this.showErrorToast('Failed', error.body?.message || error.message);
        } finally {
            this.isLoading = false;
            this.isInitialLoading = false;
        }
    }

    // Add undo handler
    async handleUndo() {
        try {
            this.isLoading = true;
            
            if(this.lastActionType === 'revokePermissionSets') {
                await undoRevokePermissionSets({ userId: this.selectedUserId });
            } else if(this.lastActionType === 'resetSystemPermissions') {
                await undoResetSystemPermissions({ userId: this.selectedUserId });
            }
            
            this.showToast('Undo Successful', 'Previous action has been reverted', 'success');
            this.showUndoButton = false;
            await this.refreshData();
            
        } catch(error) {
            this.showErrorToast('Undo Failed', error.body?.message || error.message);
        } finally {
            this.isLoading = false;
        }
    }

    // Add new property for initial load
    @track isInitialLoading = false;

    get isInitialLoadingOrIsLoading() {
        return this.isInitialLoading || this.isLoading;
    }
    get showSearchWarning() {
        return this.searchTerm && this.totalObjectRecords >= 2000;
    }

    // Add data reset method
    async refreshData() {
        try {
            this.isLoading = true;
            await this.loadUserDetails();
            await Promise.all([
                this.loadRiskAnalysis(),
                this.loadObjectPermissions(),
                this.loadFieldPermissions(),
                this.loadSystemPermissions()
            ]);
        } catch(error) {
            this.showErrorToast('Refresh Failed', error.body?.message || error.message);
        } finally {
            this.isLoading = false;
        }
    }

    // Improved error message handler
    getErrorMessage(error) {
        return error.body?.message || 
               error.message || 
               'Unknown error occurred while loading user data';
    }

    handleCopyToExcel() {
        try {
            // Get visible columns and their field names
            const columns = this.objectColumns.map(col => col.label);
            const fields = this.objectColumns.map(col => col.fieldName);

            // Create CSV/TSV content
            const csvContent = [
                columns.join('\t'), // Use tab separator for Excel
                ...this.filteredObjectPermissions.map(row => 
                    fields.map(field => {
                        // Handle nested objects (like links) and formatted values
                        const value = row[field];
                        return typeof value === 'object' ? 
                            (value.value || value.label || '') : 
                            (value || '');
                    }).join('\t')
                )
            ].join('\n');

            // Create temporary element for clipboard copy
            const textArea = document.createElement('textarea');
            textArea.value = csvContent;
            document.body.appendChild(textArea);
            textArea.select();
            
            // Execute copy command
            if (document.execCommand('copy')) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: 'Data copied to clipboard - paste into Excel',
                    variant: 'success'
                }));
            } else {
                throw new Error('Clipboard copy failed');
            }
            
            document.body.removeChild(textArea);
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error Copying Data',
                message: error.message,
                variant: 'error'
            }));
        }
    }
}



//WORKING GOOD FOR THE COPY TO EXCEL 1181