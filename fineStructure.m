classdef fineStructure < handle
    %FINESTRUCTURE Defines a class that represents the fine structure and
    %hyperfine structure of a state in an alkali metal atom
    properties
        species         %The species of atom
        numStates       %The total number of states
        
        L               %The orbital angular momentum
        J               %The orbital + electron spin angular momentum
        I               %The nuclear angular momentum
        
        gI              %The nuclear g-factor
        gJ              %The orbital+electron g-factor
        A1              %The magnetic dipole constant in MHz
        A2              %The electric quadrupole constant in MHz
        
        E               %The state energies
        H0              %The bare Hamiltonian in the uncoupled basis |mJ,mI>
        U1int           %The transformation unitary from the "internal" basis with magnetic field to the uncoupled basis
        U31             %The transformation unitary from the uncoupled basis to the |F,mF> basis
        U3int           %The transformation unitary from the "internal" basis to the |F,mF> basis
        BV1             %The basis vectors of the uncoupled basis listed as [mJ,mI]
        BV3             %The basis vectors of the |F,mF> basis listes as [F,mF]
    end
    
    properties(Constant)
        S = 0.5;        %The spin of the electron
    end

    methods
        function self = fineStructure(species,L,J)
            %FINESTRUCTURE Creates an object of class FINESTRUCTURE
            %
            %   FS = FINESTRUCTURE(SPECIES,L,J) creates a FINESTRUCTURE
            %   object FS corresponding to SPECIES and with orbital angular
            %   momentum L and orbital+electron spin angular momentum J.
            %   SPECIES can be one of 'Rb87', 'K40', or 'K41'.
            self.L = L;
            self.J = J;
            if strcmpi(species,'Rb87')
                self.species = 'Rb87';
                self.I = 3/2;
                self.gI = -0.0009951414;
            elseif strcmpi(species,'K40')
                self.species = 'K40';
                self.I = 4;
                self.gI = 0.000176490;
            elseif strcmpi(species,'K41')
                self.species = 'K41';
                self.I = 3/2;
                self.gI = 0.000176490;
            end
            
            if self.L == 0
                %
                % L = 0 is a ground state
                %
                self.setGroundState;
            else
                %
                % L ~= 0 is an excited stae
                %
                self.setExcitedState;
            end
            %
            % Calculate the Lande g-factor and the number of states
            %
            self.gJ = self.calcLandeJ(self.S,self.L,self.J);
            self.numStates = (2*self.I+1)*(2*self.J+1);
            %
            % Solve for the hyperfine states in the absence of a magnetic
            % field just so that the necessary vectors are populated
            % correctly
            %
            self.solveHyperfine(0);
        end
        
        function self = makeH0(self)
            %MAKEH0 Creates the "bare" Hamiltonian in the absence of a
            %magnetic field
            %
            %   FS = FS.MAKEH0 creates the "bare" Hamiltonian
            
            %
            % Create the basis vectors in the "uncoupled basis of |mJ,mI>
            %
            numI = 2*self.I+1;
            numJ = 2*self.J+1;
            nDim = self.numStates;
            mJ = -self.J:self.J;
            mI = -self.I:self.I;
            self.BV1=[reshape(repmat(mJ,numI,1),nDim,1) repmat(mI(:),numJ,1)];  %Uncoupled basis |mJ,mI>
            %
            % I-J coupled basis |F,mF>. Ordered by increasing energy for low magnetic fields
            %
            self.BV3 = zeros(nDim,2);
            if self.A1 > 0
                %
                % If A1 > 0 then larger F corresponds to higher energies
                %
                F = abs(self.I-self.J):abs(self.I+self.J);
            else
                %
                % If A1 < 0 then larger F corresponds to smaller energies
                %
                F = abs(self.I+self.J):-1:abs(self.I-self.J);
            end
            %
            % Populate basis vector with mF labels based on Lande g-factor
            % for each hyperfine manifold
            %
            mm=1;
            for nn=1:numel(F)
                gF = self.calcLandeF(self.I,self.J,F(nn),self.gI,self.gJ);
                if gF > 0
                    %
                    % If gF > 0 then higher mF values are higher in energy
                    %
                    mF = -F(nn):F(nn);
                else
                    %
                    % If gF < 0 then higher mF values are lower in energy
                    %
                    mF = F(nn):-1:-F(nn);
                end
                %
                % This puts the state labels in the correct location in the
                % BV3 array
                %
                self.BV3(mm:(mm+2*F(nn)),:) = [F(nn)*ones(2*F(nn)+1,1) mF(:)];
                mm = mm+2*F(nn)+1;
            end
            %
            % Transformation matrix from uncoupled |mJ,mI> basis to the coupled |F,mF> basis
            % Inverse is the hermitian conjugate
            %
            self.U31 = zeros(nDim);
            for a = 1:nDim
                F = self.BV3(a,1);
                mF = self.BV3(a,2);
                for b = 1:nDim
                    mJ = self.BV1(b,1);
                    mI = self.BV1(b,2);
                    if (abs(mI + mJ) > F) || ((mI + mJ) ~= mF)
                        %
                        % Sum of m values must the equal. Also mI + mJ must
                        % always be less than F
                        %
                        continue;
                    else
                        self.U31(a,b) = ClebschGordan(self.I,self.J,F,mI,mJ,mF);
                    end
                end
            end
            %
            % Finally calculate the bare Hamiltonian in the uncoupled basis
            % Based on Steck's Rubidium data https://steck.us/alkalidata/rubidium87numbers.1.6.pdf
            % equation 15
            %
            H = zeros(nDim);
            F = abs(self.I-self.J):abs(self.I+self.J);
            for a=1:nDim
                mJ1 = self.BV1(a,1);
                mI1 = self.BV1(a,2);
                for b = 1:nDim
                    mJ2 = self.BV1(b,1);
                    mI2 = self.BV1(b,2);
                    for c = 1:numel(F)
                        if (abs(mI1 + mJ1) > F(c)) || (abs(mI2 + mJ2) > F(c)) || ((mI1 + mJ1) ~= (mI2 + mJ2))
                            continue;
                        end
                            CG = ClebschGordan(self.I,self.J,F(c),mI1,mJ1,mI1+mJ1).*ClebschGordan(self.I,self.J,F(c),mI2,mJ2,mI2+mJ2);
                            K = F(c)*(F(c)+1)-self.I*(self.I+1)-self.J*(self.J+1);
                            if self.J >= 1 && self.I >= 1 && self.L > 0
                                %
                                % This only applies for L > 0, I > 1, and J
                                % > 1. Needs a conditional otherwise we get
                                % a NaN value
                                %
                                tmp = CG*(self.A1/2*K+self.A2*(1.5*K*(K+1)-2*self.I*self.J*(self.I+1)*(self.J+1))./(4*self.I*self.J*(2*self.I-1)*(2*self.J-1)));
                            else
                                tmp = CG*self.A1/2*K;
                            end
                            H(a,b) = H(a,b)+tmp;
                    end
                end
            end
            %
            % Assign calculated Hamiltonian to H0
            %
            self.H0 = H;
        end
        
        function [E,U1int] = solveHyperfine(self,B)
            %SOLVEHYPERFINE Solves the hyperfine + Zeeman Hamiltonian for
            %the energies and eigenvectors
            %
            %   E = FS.SOLVEHYPERFINE(B) Solves the Hamiltonian for a given
            %   magnetic field B (in Gauss) for energies in E in MHz. Is a
            %   vector of energies ordered from lowest to highest
            %
            %   {E,U1int] = FS.SOLVEHYPERFINE(B) Generates a diagonal
            %   matrix of energies E in MHz and a transformation unitary
            %   U1int which takes vectors in the basis that solves the
            %   hyperfine + Zeeman Hamiltonian and transforms them to the
            %   uncoupled basis |mJ,mI>
            %

            %
            % If H0 doesn't exist, make it
            %
            if numel(self.H0) == 0
                self.makeH0;
            end
            %
            % Calculate Zeeman field
            %
            if B == 0
                %
                % No field case is diagonal in |F,mF> basis
                %
                E = self.U31*self.H0*(self.U31');
                U1int = self.U31';
            else
                %
                % With a field it is not diagonal in either basis
                %
                HB = diag(const.muBh*B*(self.gJ*self.BV1(:,1)+self.gI*self.BV1(:,2)));
                H2 = self.H0+HB;
                [U1int,E] = eig(H2);  
            end
            
            self.E=E;
            self.U1int=U1int;
            self.U3int=self.U31*self.U1int;
            if nargout <= 1
                E = diag(E);
            end
        end
        
        
    end

    methods(Access = protected)
        function self = setGroundState(self)
            %SETGROUNDSTATE Sets properties correctly for a ground state
            % (L = 0).
            %
            %   FS = FS.SETGROUNDSTATE() Sets the ground state properties
            self.A2 = 0;
            if strcmpi(self.species,'Rb87')
                self.A1 = 6834.682610904/(self.I+self.S);
            elseif strcmpi(self.species,'K40')
                self.A1 = -285.7308;
            elseif strcmpi(self.species,'K41')
                self.A1 = 254.013872/(self.I+self.S);
            end
        end
        
        function self = setExcitedState(self)
            %SETEXCITEDSTATE Sets properties correctly for an excited state
            % (L = 0).
            %
            %   FS = FS.SETEXCITEDSTATE() Sets the excited state properties
            if self.J == 0.5
                self.A2 = 0;
                if strcmpi(self.species,'Rb87')
                    self.A1 = 6834.682610904/(self.I+self.S);
                elseif strcmpi(self.species,'K40')
                    self.A1 = -285.7308;
                elseif strcmpi(self.species,'K41')
                    self.A1 = 254.013872/(self.I+self.S);
                end
            elseif self.J == 1.5
                if strcmpi(self.species,'Rb87')
                    self.A1 = 84.7185;
                    self.A2 = 12.4965;
                elseif strcmpi(self.species,'K40')
                    self.A1 = -7.585;
                    self.A2 = -3.445;
                elseif strcmpi(self.species,'K41')
                    self.A1 = 3.363;
                    self.A2 = 3.351;
                end
            end
        end
    end

    
    methods(Static)
        function gJ = calcLandeJ(S,L,J)
            %CALCLANDEJ Calculates the Lande g-factor for a J state
            %
            %   gJ = CALCLANDE(S,L,J) calculates the Lande g-factor for the
            %   state labelled with electron spin S, orbital angular
            %   momentum L and total angular momentum J
            gJ = (J.*(J+1)-S*(S+1)+L*(L+1))./(2*J.*(J+1))+2*(J.*(J+1)+S*(S+1)-L*(L+1))/(2*J*(J+1));
        end
        
        function gF = calcLandeF(I,J,F,gI,gJ)
            %CALCLANDEF Calculates the Lande g-factor for an F state
            %
            %   gF = CALCLANDE(I,J,F,gI,gJ) calculates the Lande g-factor for the
            %   state labelled with nuclear spin I, angular+electron spin
            %   J, and total angular momentum F with nuclear g-factor gI
            %   and J g-factor gJ
            gF = gJ*(F.*(F+1)-I*(I+1)+J*(J+1))./(2*F.*(F+1))+gI*(F.*(F+1)+I.*(I+1)-J.*(J+1))./(2*F.*(F+1));
        end
    end
    
    
    
end