classdef densityMatrix < handle
    %DENSITYMATRIX Defines a class that can be used for solving
    %time-dependent equations related to density matrices
    %
    %   This class assumes that these problems look like optical
    %   transitions where there is a ground and an excited state
    
    properties
        numStates           %Total number of states
        density             %The density matrix
        densityVec          %The vectorized density matrix (2D -> 1D)
        initPop             %The initial populations
        bare                %The bare Hamiltonian
        coupling            %The coupling Hamiltonian
        decay               %The decay Hamiltonian
        lindblad            %The Lindblad term representing spontaneous decay
        
        dt                  %The time step to use
        T                   %The total time to integrate
        t                   %The time vector
    end
    
    methods
        function self = densityMatrix(numStates)
            %DENSITYMATRIX creates an instance of the class
            %
            %   D = DENSITYMATRIX creates a bare instance of the class
            %
            %   D = DENSITYMATRIX(NUMSTATES) creates an
            %   instance of the class with total number of states NUMSTATES
            if nargin == 1
                self.setNumStates(numStates);
            end
        end
        
        function self = setNumStates(self,numStates)
            %SETNUMSTATES Sets the number of states and pre-allocates
            %arrays
            %
            %   D = D.SETNUMSTATES(NUMSTATES) uses the total number 
            %   of states NUMSTATES to pre-allocate arrays
            self.numStates = numStates;
            self.density = zeros(self.numStates);
            self.bare = zeros(self.numStates);
            self.coupling = zeros(self.numStates);
            self.decay = zeros(self.numStates);
            self.initPop = zeros(self.numStates,1);
        end
        
        function P = getPopFromVec(self)
            %GETPOPFROMVEC Returns the populations as a function of time
            %from the flattened density matrix
            %
            %   P = D.GETPOPFROMVEC() Returns the populations (rows) as a
            %   function of time (columns)
            P = self.densityVec(1:(self.numStates+1):self.numStates^2,:);
        end
        
        function P = getPopulations(self,opt)
            %GETPOPULATIONS Returns the populations as a function of time
            %from the solved density matrix equations
            %
            %   P = D.GETPOPULATIONS(OPT) Uses OPT to get the populations.
            %   If OPT is not supplied, it returns all populations. If OPT is
            %   numeric, it returns only those populations specified by the
            %   index given in OPT
            if nargin == 1 || isempty(opt)
                P = self.getPopFromVec;
            elseif isnumeric(opt)
                pTemp = self.getPopFromVec;
                P = pTemp(opt(:),:);
            end 
            P = real(P);
        end
        
        function plotPopulations(self,opt)
            %PLOTPOPULATIONS Plots the populations as a function of time
            %
            %   D.plotPopulations() plots all populations as a function of
            %   time on the current axes
            %
            %   D.plotPopulations(OPT) plots the populations given by OPT
            %   on the current axes.  Valid values for OPT are the same as
            %   for GETPOPULATIONS
            if nargin == 1
                opt = [];
            end
            P = self.getPopulations(opt);
            ax = gca;
            grid on;
            set(ax,'NextPlot','ReplaceChildren','LineStyleOrder',{'-','--','.-'})
            plot(ax,self.t,P,'linewidth',2);
            legend(ax,self.getPopLegend(opt),'interpreter','tex');
            xlabel('Time [s]');
            ylabel('Population');
        end
        
        function str = getPopLegend(self,opt)
            %GETPOPLEGEND Returns a cell array that can be used as a legend
            %for a plot of populations
            %
            %   STR = D.GETPOPLEGEND() Returns a cell array of strings that
            %   is a legend for all populations
            %
            %   STR = D.GETPOPLEGEND(OPT) Returns a cell array of strings
            %   that is a legend for only those populations specified by
            %   OPT.  Valid values for OPT are the same as for
            %   GETPOPULATIONS
            %
            if nargin == 1 || isempty(opt)
                idx = 1:self.numStates;
            elseif isnumeric(opt)
                idx = opt;
            end
            str = cell(length(idx),1);
            for nn = 1:length(idx)
                str{nn} = sprintf('\\rho_{%d%d}',idx(nn),idx(nn));
            end
        end
        
        
        function self = integrate(self,dt,T,method)
            %INTEGRATE Integrates the master equation for a given time
            %step and for a given total time
            %
            %   D = D.INTEGRATE(DT,T) Integrates the master equation
            %   for the density matrix as a function of time for a time
            %   step DT and for a total time T
            %
            %   D = D.INTEGRATE(__,METHOD) uses METHOD for integration.
            %   Use 'normal' or 'exp' for expm() and 'fast' for simple
            %   inverse
            self.dt = dt;
            self.T = T;
            self.t = 0:self.dt:self.T;
            numSteps = numel(self.t);
            %
            % Initialize values
            %
            M = self.makeM;
            self.densityVec = zeros(self.numStates^2,numSteps);
            tmp = real(self.initPop);
            self.density = diag(tmp./sum(tmp));
            self.densityVec(:,1) = self.density(:);
            if any(isnan(self.densityVec(:,1)))
                error('NaNs encountered in initial density state');
            end
            %
            % Integrate for the density matrix
            %
            %D_exp=(eye(size(M))-M*self.dt/2)\(eye(size(M))+M*self.dt/2);
            if nargin < 4 || strcmpi(method,'exp') || strcmpi(method,'normal')
                D_exp = expm(M*dt);
                for n = 2:numSteps
                    self.densityVec(:,n) = D_exp*self.densityVec(:,n-1);
                end
            elseif strcmpi(method,'fast')
                I = eye(size(M));
                for n = 2:numSteps
                    self.densityVec(:,n) = (I - M*dt/2)\(I + M*dt/2)*self.densityVec(:,n-1);
                end
            else
                error('Unknown method ''%s''!',method);
            end
        end
        
        function self = solveSteadyState(self)
            %SOLVESTEADYSTATE Solves for the steady-state solution of the
            %master equation
            %
            %   D = D.SOLVESTEADYSTATE Solves for the steady state solution
            M = self.makeM;
            %
            % This creates the necessary constraint that the sum of the
            % populations must be 1
            %
            a = diag(ones(self.numStates,1));
            M(end+1,:) = a(:)';
            b = zeros(size(M,1),1);
            b(end) = 1;
            %
            % Calculate the steady state solution as the solution to Mv = b
            %
            self.densityVec = M\b;
            self.density = reshape(self.densityVec,self.numStates,self.numStates);
        end
        
        function M = makeM(self)
            %MAKEM Makes the matrix describing the master equation
            %
            %   M = D.MAKEM() Makes the matrix M describing the master
            %   equation
            if numel(self.lindblad) == 0
                %
                % Create the Linblad term only if it hasn't already been
                % created
                %
                self.makeTotalLindblad;
            end
            M = self.flattenUnitary + self.lindblad;
        end
        
        function M = flattenUnitary(self)
            %FLATTENUNITARY Flattens the unitary part of the Hamiltonian.
            %This takes the bare and coupling Hamiltonians and computes
            %d_t \rho_{ab} = i<a|[\rho,H]|b>
            %
            %   M = D.FLATTENUNITARY Computes the flattened unitary matrix
            %   describing the evolution of the density matrix
            M = zeros(self.numStates^2);
            for n = 1:self.numStates
                for m = 1:self.numStates
                    row = m+(n-1)*self.numStates;       
                    for j = 1:self.numStates
                        col = j+(n-1)*self.numStates;
                        M(row,col) = M(row,col)-1i*(self.bare(j,m)+self.coupling(j,m));
                        col = m+(j-1)*self.numStates;
                        M(row,col) = M(row,col)+1i*(self.bare(n,j)+self.coupling(n,j));       
                    end
                end
            end
        end
        
        function L = makeTotalLindblad(self)
            %MAKETOTALLINDBLAD Creates the total Lindblad term
            %
            %   L = D.MAKETOTALLINDBLAD() Returns the total Lindblad term L
            L = zeros(self.numStates^2);
            for n = 1:self.numStates
                for m = n:self.numStates
                    L = L + self.makeLindblad(n,m);
                end
            end
            self.lindblad = L;
        end
        
        function L = makeLindblad(self,g,e,decay_in)
            %MAKELINDBLAD Creates the Lindblad term for a pair of ground
            %and excited states
            %
            %   L = D.MAKELINDBLAD(G,E) Creates the Lindblad term for decay
            %   from state E to state G
            %
            %   L = D.MAKELINDBLAD(G,E,DECAY_IN) Creates the Lindblad term
            %   using the supplied decay matrix
            %
            if nargin < 4
                decay_in = self.decay;
            end
            L = zeros(self.numStates^2);
            for n = 1:self.numStates
                for m = 1:self.numStates
                    row = m + (n-1)*self.numStates;
                    if (n == g) && (m == g)
                        col = e + (e-1)*self.numStates;
                        L(row,col) = L(row,col) + decay_in(g,e);
                    end       
                    if n == e
                        col = m + (e-1)*self.numStates;
                        L(row,col) = L(row,col) - 0.5*decay_in(g,e);
                    end        
                    if m == e
                        col = e+(n-1)*self.numStates;
                        L(row,col) = L(row,col) - 0.5*decay_in(g,e);
                    end        
                end
            end
        end
    end
    
end